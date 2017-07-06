<#
	.SYNOPSIS
		put data into buckets

	.PARAM KeyFunctions
		most key functions will look something like 
		{ param ($data) if($data -match 'some(regex)') { 'match' } }

		Tip: for quick and good effect effect, the key should be a number.

		the default key function will look for the first number in the data and emit that as its key.

	.PARAM SortFunction
		custom argument to $buckets | sort $SortFunction 

		the default sort function will try to sort the data as it were a number, and fallback to alphabetic sort  

	.PARAM Width
		width of the diagram to create (the bin with the most data in it will be shown this wide)

	.PARAM ReturnData
		instead of plotting anything, return the map key -> data[]
		useful for debugging or further analysis of specific buckets
		
	.DESCRIPTION
		Data analysis tool to categorize and visualize data size.
		accepts key functions to be run on every data.
		key functions are expected to emit the key of the bucket to put the data into.
		
		data that no key is emitted for flows into the '_rest' bin.
		data that more than one key function emits a key for flows into the '_overlap' bin. 

		afterwards, a bar chart shows relative bin sizes.

	.EXAMPLE 
		1..100 | %{[System.Random]::new().Next(100)} | Bucketeer 

	.EXAMPLE 
		gc datafile.txt | Bucketeer { param($data) if($data -match 'regex (iterest)') { if(Matches[1] -gt $threshold) { 'interesting'; return } Matches[1] }}

#>
[CmdletBinding()]
Param (
	[Parameter(Mandatory=$True, ValueFromPipeline=$True)]
	$Data,

	[Parameter(Mandatory=$False, Position = 0)]
	[ScriptBlock[]]
	$KeyFunctions = { param($data) if($data -match '(\d+)') { $Matches[1] } },
	
	[Parameter(Mandatory=$False, Position = 1)]
	[ScriptBlock]
	$SortFunction = {[int]$i = 0; if([int]::TryParse($_, [ref] $i)) { $i } else { $_ }},

	[Parameter()]
	[int]
	$Width = 80,

	[Parameter()]
	[switch]
	$ReturnData = $False
)
Begin {
	$restLabel = '_rest'
	$overlapLabel = '_overlap'
	$averageLabel = 'average'
	$barChar = '#'
	
	function DebugVar { 
		Param($Name, $Value)
		Write-Debug "$($Name.PadRight(10)): $Value"	
	}
	function VerboseVar { 
		Param($Name, $Value)
		Write-Verbose "$($Name.PadRight(10)): $Value"	
	}

	function AddData {
		Param($Dict, $Key, $Data)
		
		if($Dict.ContainsKey($Key)) {
			$Dict[$Key].Add($Data)
		}
		else {
			$list = New-Object System.Collections.Generic.List[System.Object]
			$list.Add($Data)
			$Dict.Add($Key, $list)
		}
	}

	if($PSBoundParameters['Debug']){
		$DebugPreference = 'Continue'
	}
	
	Write-Debug "Begin"
	
	$buckets = @{}
	$rest = New-Object System.Collections.Generic.List[System.Object]
	$overlap = New-Object System.Collections.Generic.List[System.Object]

	foreach($key in $Order) {
		$list = New-Object System.Collections.Generic.List[System.Object]
		$buckets.Add($Key, $list)
	}
}

Process {
	$data = $_	
	VerboseVar '$data' $data
	
	$matchCount = 0;
	foreach($keyFunc in $KeyFunctions) {
		$key = &$keyFunc $data				
		
		if($key) {
			if($key -is [System.Array]) {
				foreach($i in $key) {
					VerboseVar '$key' $i	
					AddData $buckets $key $data 
					$matchCount++;		
				}
			}
			else {		
				VerboseVar '$key' $key
				AddData $buckets $key $data 
				$matchCount++;		
			}
		}
	}

	if($matchCount -eq 0) { 
		Write-Verbose "data matches no bucket"
	    $rest.Add($data)
	}
	if($matchCount -gt 1) {
		Write-Verbose "data overlaps $matchCount buckets"
		$overlap.Add($data)
	}
}

End {
	Write-Debug "End"
	
	if($ReturnData)	{
			$buckets.Add($restLabel, $rest)
			$buckets.Add($overlapLabel, $overlap)

		$buckets
		Exit
	}
	
	# line everything up nice
	$measure = $buckets.Values | %{ $_.Count } | Measure-Object -Average -Maximum -Minimum	
	$countPadding = $measure.Maximum.ToString().Length
	
	$labelPadding = ($buckets.Keys | %{ $_.Length } |  Measure-Object -Maximum).Maximum 
	if($overlapLabel.Length -gt $labelPadding){ $labelPadding = $overlapLabel.Length }
	if($restLabel.Length -gt $labelPadding){ $labelPadding = $restLabel.Length }

	DebugVar '$labelPadding' $labelPadding
	DebugVar '$countPadding' $countPadding

	
	# print special 'bucket' data
	(@{ Label=$restLabel; Count=$rest.Count }),(@{ Label=$overlapLabel; Count=$overlap.Count }),(@{ Label=$averageLabel; Count=$measure.Average }),(@{ Label=$barChar; Count=([decimal]$measure.Maximum / [decimal]$Width) }) | %{
		$labelPadded = $_.Label.PadLeft($labelPadding + 4)			
		"$labelPadded : $($_.Count)"
	}
		
	# heder line 
	"".PadRight($labelPadding + $countPadding + $Width + 5, '=') 
	
	# bucket data output		
	foreach($key in ($buckets.Keys | sort $SortKeys)) {
		$datawidth = ( [decimal]$buckets[$key].Count / [decimal]$measure.Maximum ) * $Width
		DebugVar '$datawidth' $datawidth

		$labelPadded = $key.PadLeft($labelPadding)
		$countPadded = $buckets[$key].Count.ToString().PadLeft($countPadding)
		$barVisual = ''.PadRight($datawidth, $barChar)

		"$labelPadded ($countPadded): $barVisual"
	}
}	