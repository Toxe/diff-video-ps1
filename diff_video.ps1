# & .\diff_video.ps1 video1 video2 output.mp4

$PSStyle.Progress.View = 'Classic'

function WithProgress {
    param (
        [Parameter(ValueFromPipeline)] $input,
        [Parameter(Mandatory)] [string]$Activity,
        [Parameter(Mandatory)] [int]$MaxCounter,
        [string]$StatusText = 'completed',
        [ScriptBlock]$Begin = { },
        [ScriptBlock]$Process = { },
        [ScriptBlock]$End = { },
        [ScriptBlock]$PercentComplete = { [math]::Round(100.0 * $counter / $MaxCounter) },
        [ScriptBlock]$UpdateCounter = { $counter + 1 }
    )

    begin {
        $counter = 0

        & $Begin

        $percent = & $PercentComplete
        $status = '{0}/{1} {2} ({3}%)' -f $counter, $MaxCounter, $StatusText, $percent
        Write-Progress -Activity $Activity -Status $status -PercentComplete $percent
    }

    process {
        $counter = & $UpdateCounter

        & $Process $input

        $percent = & $PercentComplete
        $status = '{0}/{1} {2} ({3}%)' -f $counter, $MaxCounter, $StatusText, $percent
        Write-Progress -Activity $Activity -Status $status -PercentComplete $percent
    }

    end {
        & $End
        Write-Progress -Activity $Activity -Completed
    }
}

function Die {
    param (
        [int]$exitcode,
        [string]$message
    )

    Write-Error "Error: $message"
    Exit $exitcode
}

function ShowDuration {
    param (
        [datetime]$t
    )

    Write-Host ('--> {0:n3} seconds' -f (((Get-Date) - $t).TotalSeconds))
    Write-Host ''
}

function EvalArgs {
    param (
        [array]$params
    )

    if ($params.Count -lt 3) { Die 1 'Missing arguments' }

    return $params[0], $params[1], $params[2]
}

function GetNumberOfCoresAndThreads {
    $num_cores = ([Environment]::ProcessorCount)
    $imagick_threads = 2
    $ffmpeg_threads = [int]($num_cores / 2)
    Write-Host "CPU cores: $num_cores"
    Write-Host "ImageMagick threads: $imagick_threads"
    Write-Host "FFmpeg threads: $ffmpeg_threads"

    return $num_cores, $imagick_threads, $ffmpeg_threads
}

function InputVideoMustExist {
    param (
        [string]$video
    )

    if (-Not (Test-Path $video)) { Die 2 "Video not found: $video" }
    Write-Host "input video: $video"
}

function OutputVideoMustNotExist {
    param (
        [string]$video
    )

    if (Test-Path $video) { Die 3 "Output video already exists: $video" }
    Write-Host "output video: $video"
}

function CreateTempWorkDirectory {
    $temp_dir = [System.IO.Path]::GetTempPath()
    $random_name = [System.IO.Path]::GetRandomFileName()
    $work_dir = Join-Path -Path "$temp_dir" -ChildPath "$random_name"
    New-Item -Path "$work_dir" -ItemType Directory | Out-Null
    Write-Host "work directory: $work_dir"

    return $work_dir
}

function ExtractFrames {
    param (
        [string]$work_dir,
        [string]$video1,
        [string]$video2,
        [int]$ffmpeg_threads
    )

    Write-Host ''
    Write-Host 'extracting frames...'
    $t0 = Get-Date

    $videos = @(
        @($video1, 'a'),
        @($video2, 'b')
    )

    $videos | ForEach-Object -Parallel {
        $video = $_[0]
        $postfix = $_[1]
        $frames = Join-Path -Path "${using:work_dir}" -ChildPath "%06d_${postfix}.png"
        ffmpeg -v error -i "$video" -threads $using:ffmpeg_threads "$frames"
    }

    $video1_number_of_frames = (Get-ChildItem -Path "$work_dir" -Name -File -Filter *_a.png).Length
    $video2_number_of_frames = (Get-ChildItem -Path "$work_dir" -Name -File -Filter *_b.png).Length
    Write-Host "video 1 frames: $video1_number_of_frames"
    Write-Host "video 2 frames: $video2_number_of_frames"

    ShowDuration $t0
    return $video1_number_of_frames
}

function GenerateDiffs {
    param (
        [string]$work_dir,
        [int]$number_of_frames,
        [int]$num_cores,
        [int]$imagick_threads
    )

    Write-Host 'generating diffs...'
    $t0 = Get-Date

    1..$number_of_frames | ForEach-Object -ThrottleLimit $num_cores -Parallel {
        $id = '{0:d6}' -f $_
        $frame = Join-Path -Path "${using:work_dir}" -ChildPath "${id}"
        magick -limit thread $using:imagick_threads "${frame}_a.png" "${frame}_b.png" -compose difference -composite -evaluate Pow 2 -evaluate divide 3 -separate -evaluate-sequence Add -evaluate Pow 0.5 "${frame}_d.png"
        $_
    } | WithProgress -Activity 'generating diffs...' -MaxCounter $number_of_frames

    ShowDuration $t0
}

function CalculateMinMaxIntensity {
    param (
        [string]$work_dir,
        [int]$number_of_frames,
        [int]$num_cores,
        [int]$imagick_threads
    )

    Write-Host 'calculating min/max intensity...'
    $t0 = Get-Date

    $lines = 1..$number_of_frames | ForEach-Object -ThrottleLimit $num_cores -Parallel {
        $id = '{0:d6}' -f $_
        $frame = Join-Path -Path "${using:work_dir}" -ChildPath "${id}"
        $output = magick identify -limit thread $using:imagick_threads -format '%[min] %[max]\n' "${frame}_d.png"
        $output
    } | WithProgress -Activity 'calculating min/max intensity...' -MaxCounter $number_of_frames -Process { $_ }

    $min_intensity = [int]::MaxValue
    $max_intensity = [int]::MinValue

    $lines | ForEach-Object {
        $a, $b = $_ -split ' '
        $min_intensity = [math]::min($a, $min_intensity)
        $max_intensity = [math]::max($b, $max_intensity)
    }

    Write-Host "min intensity: $min_intensity"
    Write-Host "max intensity: $max_intensity"

    ShowDuration $t0
    return $min_intensity, $max_intensity
}

function NormalizeDiffs {
    param (
        [string]$work_dir,
        [int]$number_of_frames,
        [int]$num_cores,
        [int]$imagick_threads,
        [int]$min_intensity,
        [int]$max_intensity
    )

    Write-Host 'normalizing diffs...'
    $t0 = Get-Date

    1..$number_of_frames | ForEach-Object -ThrottleLimit $num_cores -Parallel {
        $id = '{0:d6}' -f $_
        $frame = Join-Path -Path "${using:work_dir}" -ChildPath "${id}"
        magick -limit thread $using:imagick_threads "${frame}_d.png" -level "$using:min_intensity,$using:max_intensity" "${frame}_n.png"
        $_
    } | WithProgress -Activity 'normalizing diffs...' -MaxCounter $number_of_frames

    ShowDuration $t0
}

function RenderOutputVideo {
    param (
        [string]$work_dir,
        [string]$output_video,
        [int]$number_of_frames
    )

    Write-Host 'rendering output video...'
    $t0 = Get-Date

    ffmpeg -v error -nostats -hide_banner -progress pipe:1 -framerate 60000/1001 -i "$work_dir\%06d_n.png" -vf 'colorchannelmixer=.0:.0:.0:0:.0:1:.0:0:.0:.0:.0:0' -c:v libx264 -crf 18 -preset veryfast "$output_video" |
        Where-Object { $_ -match 'frame=(\d+)' } |
        ForEach-Object { $Matches[1] } |
        WithProgress -Activity 'rendering output video...' -MaxCounter $number_of_frames -StatusText 'frames' -UpdateCounter { $_ }

    ShowDuration $t0
}

function DeleteTempWorkDirectory {
    param (
        [string]$work_dir
    )

    Write-Host 'cleaning up...'

    $t0 = Get-Date
    Remove-Item -Path "$work_dir" -Recurse
    ShowDuration $t0
}

$VIDEO1, $VIDEO2, $OUTPUT_VIDEO = EvalArgs $args
$num_cores, $imagick_threads, $ffmpeg_threads = GetNumberOfCoresAndThreads
InputVideoMustExist $VIDEO1
InputVideoMustExist $VIDEO2
OutputVideoMustNotExist $OUTPUT_VIDEO
$work_dir = CreateTempWorkDirectory

$number_of_frames = ExtractFrames $work_dir $VIDEO1 $VIDEO2 $ffmpeg_threads
GenerateDiffs $work_dir $number_of_frames $num_cores $imagick_threads
$min_intensity, $max_intensity = CalculateMinMaxIntensity $work_dir $number_of_frames $num_cores $imagick_threads
NormalizeDiffs $work_dir $number_of_frames $num_cores $imagick_threads $min_intensity $max_intensity
RenderOutputVideo $work_dir $OUTPUT_VIDEO $number_of_frames

DeleteTempWorkDirectory $work_dir
