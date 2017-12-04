<#
	.SYNOPSIS
		puts data into buckets, then visualizes relative bucket sizes (like a histogram or spectrum)

	.PARAMETER Data
		The data to analyze (e.g. lines in a file)
		When -Render is set, this is the hashTable[key] => [] as retured by -ReturnData

	.PARAMETER KeyFunctions
		most key functions will look something like 
		{ param ($data) if($data -match 'some(regex)') { 'match' } }

		Tip: for quick and good effect effect, the key should be an int.
		the default key function will emit the first number in a data and emit that as key.

	.PARAMETER SortFunction
		custom argument to $buckets | sort $SortFunction 

		the default function tries to interpret bucket names (keys) as ints and will fallback to alphanumeric bucket key sort 

	.PARAMETER Width
		width of the diagram to create (the bin with the most data will be shown this wide)

	.PARAMETER ReturnData
		instead of plotting anything, return the map[key] -> data[]
		useful for debugging or further analysis of specific buckets
		
	.PARAMETER Render
		instead of bucketeering, take a map[key] -> data[]
		and render it into a histogram

	.PARAMETER AbsoluteWidth
		make the bar width a fraction of the total data count 
		(instead of the largest bucket data count)

		This is can be useful when there's a few huge and lots of small buckets
		
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
	
	.EXAMPLE
		$data = gc datafile.txt | Bucketeer -ReturnData
		$data | Bucketeer -Render		

	.EXAMPLE
		$keyFunc = { param($data) if($data -match '(\d+)') { $Matches[1]; $Matches[2] } }
		$data = gc datafile.txt | Bucketeer $keyFunc -ReturnData
		&$keyFunc $data['_overlap'][0]		
		
		Description
		-----------
		example keyFunc debugging setup
		put the keyFunc in a variable, then inspect individual data
		
	.EXAMPLE
		$SortByCount = { -$_.Value.Count } 
		data | Bucketeer -SortFunction $SortByCount
		
		Description
		-----------
		sort function that sorts buckets by data count DESC	
#>
[CmdletBinding(DefaultParameterSetName = 'Bucketeer')]
Param (
	[Parameter(Mandatory=$True, ValueFromPipeline=$True, ParameterSetName='Bucketeer')]
	[Parameter(Mandatory=$True, ValueFromPipeline=$True, ParameterSetName='Render')]
	$Data,

	[Parameter(Mandatory=$False, Position = 0, ParameterSetName='Bucketeer')]
	[ScriptBlock[]]
	$KeyFunctions = { param($data) if($data -match '(\d+)') { $Matches[1] } },
	
	[Parameter(Mandatory=$False, Position = 1, ParameterSetName='Bucketeer')]
	[Parameter(Mandatory=$False, Position = 1, ParameterSetName='Render')]
	[ScriptBlock]
	$SortFunction = {[int]$i = 0; if([int]::TryParse($_.Name, [ref] $i)) { $i } else { $_ }},
	
	[Parameter(ParameterSetName='Bucketeer')]
	[switch]
	$ReturnData,

	[Parameter(Mandatory=$True, ParameterSetName='Render')]
	[switch]
	$Render,
	
	[Parameter(Mandatory=$True, ParameterSetName='Render')]
	[switch]
	$AbsoluteWidth,

	[Parameter(ParameterSetName='Bucketeer')]
	[Parameter(ParameterSetName='Render')]
	[int]
	$Width = 80
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
}

Process {
	if($PsCmdlet.ParameterSetName -eq 'Bucketeer') {
		$data = $_	
		# VerboseVar '$data' $data
	
		$matchCount = 0;
		foreach($keyFunc in $KeyFunctions) {
			$key = &$keyFunc $data				
		
			if($key) {
				if($key -is [System.Array]) {
					foreach($i in $key) {
						# VerboseVar '$key' $i	
						AddData $buckets $key $data 
						$matchCount++;		
					}
				}
				else {		
					# VerboseVar '$key' $key
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
	else { # $PsCmdlet.ParameterSetName -eq 'Render'
		$buckets = $_		
		VerboseVar '$buckets' $buckets
		if($buckets -isnot [hashTable]) { Write-Error "can only render hashTables[key] => []"; exit } 


		if($buckets.ContainsKey($overlapLabel)) {
			Write-Verbose "found $overlapLabel"
			$overlap = $buckets[$overlapLabel]
			$buckets.Remove($overlapLabel)
		}

		if($buckets.ContainsKey($restLabel)) {
			Write-Verbose "found $restLabel"
			$rest = $buckets[$restLabel]
			$buckets.Remove($restLabel)
		}

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
	$measure = $buckets.Values | %{ $_.Count } | Measure-Object -Average -Maximum -Minimum -Sum
	
	$maxwidth = $measure.Maximum
	if($AbsoluteWidth) {
		$maxwidth = $measure.Sum
	}
	
	$countPadding = "$maxwidth".Length # measure-null-proof ToString()
	$labelPadding = ($buckets.Keys | %{ $_.Length } |  Measure-Object -Maximum).Maximum 

	$HeaderExtraPadding = ' ()'.Length
	if(($overlapLabel.Length - $HeaderExtraPadding) -gt $labelPadding){ $labelPadding = ($overlapLabel.Length - $HeaderExtraPadding) }
	if(($restLabel.Length - $HeaderExtraPadding) -gt $labelPadding){ $labelPadding = ($restLabel.Length - $HeaderExtraPadding) }

	DebugVar '$labelPadding' $labelPadding
	DebugVar '$countPadding' $countPadding

	
	# print special 'bucket' data
	(@{ Label='total'; Count=$measure.Sum }),(@{ Label=$restLabel; Count=$rest.Count }),(@{ Label=$overlapLabel; Count=$overlap.Count }),(@{ Label=$averageLabel; Count=$measure.Average }),(@{ Label=$barChar; Count=([decimal]$maxwidth / [decimal]$Width) }) | %{
		$labelPadded = $_.Label.PadLeft($labelPadding + $HeaderExtraPadding)			
		"$labelPadded : $($_.Count)"
	}
		
	# header line 
	"".PadRight($labelPadding + $countPadding + $Width + 5, '=') 
	
	# bucket data output		
	foreach($bucket in ($buckets.GetEnumerator() | sort $SortFunction)) {
		$datawidth = ( [decimal]$bucket.Value.Count / [decimal]$maxwidth ) * $Width
		DebugVar '$datawidth' $datawidth

		$labelPadded = $bucket.Name.PadLeft($labelPadding)
		$countPadded = $bucket.Value.Count.ToString().PadLeft($countPadding)
		$barVisual = ''.PadRight($datawidth, $barChar)

		"$labelPadded ($countPadded): $barVisual"
	}
	
	if($Render){
		# we removed this data for rendering purposes, so we need to put it back
		$buckets.Add($restLabel, $rest)
		$buckets.Add($overlapLabel, $overlap)
	}
}	