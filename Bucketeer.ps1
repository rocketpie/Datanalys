<#
	.DESCRIPTION
		put data into buckets

	.EXAMPLE 
		1..100 | Bucketeer -Buckets '[1-9]','([1-9]{2})'


#>
[CmdletBinding()]
Param (
	[Parameter(Mandatory=$True, ValueFromPipeline=$True)]
	$Data,

	[Parameter(Mandatory=$True, Position = 0)]
	[string[]]
	$Buckets,

	[Parameter(Mandatory=$False, Position = 1)]
	[string[]]
	$BucketLabels,

	[Parameter()]
	[int]
	$Width = 80,

	[Parameter()]
	[switch]
	$ReturnBuckets = $False
)
Begin {
	function DebugVar { 
		Param($Name, $Value)
		Write-Debug "$($Name.PadRight(10)): $Value"	
	}

	# Bucket object definition
	function New-Bucket { 
		$result = New-Object PSObject
									  # string  identifier to display. (i.e. original bucket regex?)
		$result | Add-Member NoteProperty -Name Label -Value $null         
						  # Func<t_data, bool>  Function to determine wether or not a data belongs into this basket
		$result | Add-Member NoteProperty -Name Analyzer -Value $null   
								# List[Object]  list of data items in this basket
		$result | Add-Member NoteProperty -Name Data -Value (New-Object System.Collections.Generic.List[System.Object])
		$result
	}

	function Create-Bucket {
		Param( [string]$Pattern, [string]$Label )		
		$result = New-Bucket
		$result.Label = $Label
		
		$regex = [System.Text.RegularExpressions.Regex]::new($Pattern)			
		$result.Analyzer = { Param($Data) $regex.IsMatch($Data) }.GetNewClosure()
		
		$result
	}

	if($PSBoundParameters['Debug']){
		$DebugPreference = 'Continue'
	}
	
	Write-Debug "Begin"
	
	# augment missing bucket labels with the definiton regexs
	if($BucketLabels -eq $null) {
		Write-Debug "augmenting all bucket labels"
		$BucketLabels = $Buckets
	}
	if($BucketLabels.Length -lt $Buckets.Length) {
		for($i = $BucketLabels.Length; $i -lt $Buckets.Length; $i++) {
			Write-Debug "augmenting label for bucket $($Buckets[$i])"
			$BucketLabels += @($Buckets[$i]) 
		}	
	}

	$bucketList = @();		
	for($i = 0; $i -lt $Buckets.Length; $i++) {
		Write-Debug "creating Bucket '$($BucketLabels[$i])' for data matching /$($Buckets[$i])/"
		$bucket = Create-Bucket $Buckets[$i] $BucketLabels[$i]
	    $bucketList += @($bucket) 
	}

	$rest = New-Bucket 
	$rest.Label = 'none'	
	Write-Debug "creating Bucket '$($rest.Label)' for data matching no other bucket"

	$overlap = New-Bucket
	$overlap.label = 'overlap'
	Write-Debug "creating Bucket '$($overlap.Label)' for data that matches more than one bucket"
}

Process {
	$data = $_	
	
	#if($data -is [Microsoft.PowerShell.Commands.MatchInfo]){
	#	Write-Debug $data.GetType()
	#}

	$matchCount = 0;
	foreach($bucket in $bucketList) {
		if((&$bucket.Analyzer $data) -eq $true) {
			Write-Verbose "'$data' matches bucket '$($bucket.Label)'"
			$bucket.Data.Add($data)
			$matchCount++;
		}
	}

	if($matchCount -eq 0) { 
		Write-Verbose "'$data' matches no bucket"
	    $rest.Data.Add($data)
	}
	if($matchCount -gt 1) {
		Write-Verbose "'$data' overlaps $matchCount buckets"
		$overlap.Data.Add($data)
	}
}

End {
	Write-Debug "End"
	
	if($ReturnBuckets)	{
			$bucketList += @($rest)
			$bucketList += @($overlap)

		$bucketList
		Exit
	}
	
	# bucket data count measure
	$measure = $bucketList | %{ $_.Data.Count } | Measure-Object -Average -Maximum -Minimum
	# $measure 

	# line everything up nice
	$labelPadding = ($bucketList | %{ $_.Label.Length } |  Measure-Object -Maximum).Maximum 
	$countPadding = $measure.Maximum.ToString().Length
	DebugVar '$labelPadding' $labelPadding
	DebugVar '$countPadding' $countPadding

	
	# print special 'bucket' data
	(@{ Label=$rest.Label; Count=$rest.Data.Count }),(@{ Label=$overlap.Label; Count=$overlap.Data.Count }),(@{ Label='average'; Count=$measure.Average }),(@{ Label='#'; Count=([decimal]$measure.Maximum / [decimal]$Width) }) | %{
		$labelPadded = $_.Label.PadLeft($labelPadding + 4)			
		"$labelPadded : $($_.Count)"
	}
		
	# heder line 
	"".PadRight($labelPadding + $countPadding + $Width + 5, '=') 
	
	# bucket data output		
	foreach($bucket in $bucketList) {
		$datawidth = ( [decimal]$bucket.Data.Count / [decimal]$measure.Maximum ) * $Width
		DebugVar '$datawidth' $datawidth

		$labelPadded = $bucket.Label.PadLeft($labelPadding)
		$countPadded = $bucket.Data.Count.ToString().PadLeft($countPadding)
		$barVisual = ''.PadRight($datawidth, '#')

		"$labelPadded ($countPadded): $barVisual"
	}
}	
