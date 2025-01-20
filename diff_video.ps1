# & .\diff_video.ps1 video1 video2 output.mp4

$PSStyle.Progress.View = "Classic"

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

    Write-Host ("--> {0:n3} seconds" -f (((Get-Date) - $t).TotalSeconds))
}

function EvalArgs {
    param (
        [array]$params
    )

    if ($params.Count -lt 3) { Die 1 "Missing arguments" }

    return @($params[0], $params[1], $params[2])
}

function GetNumberOfCoresAndThreads {
    $num_cores = ([Environment]::ProcessorCount)
    $imagick_threads = 2
    $ffmpeg_threads = [int]($num_cores / 2)
    Write-Host "cores: $num_cores"
    Write-Host "IMagick threads: $imagick_threads"
    Write-Host "FFmpeg threads: $ffmpeg_threads"

    return @($num_cores, $imagick_threads, $ffmpeg_threads)
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

    Write-Host "extracting frames..."
    $t0 = Get-Date

    $videos = @(
        @($video1, "a"),
        @($video2, "b")
    )

    $videos | ForEach-Object -Parallel {
        $video = $_[0]
        $postfix = $_[1]
        $frames = Join-Path -Path "${using:work_dir}" -ChildPath "%06d_${postfix}.png"
        ffmpeg -v error -i "$video" -threads $using:ffmpeg_threads "$frames"
    }

    ShowDuration $t0
}

function CountNumberOfFrames {
    param (
        [string]$work_dir
    )

    $video1_number_of_frames = (Get-ChildItem -Path "$work_dir" -Name -File -Filter *_a.png).Length
    $video2_number_of_frames = (Get-ChildItem -Path "$work_dir" -Name -File -Filter *_b.png).Length
    Write-Host "video 1 frames: $video1_number_of_frames"
    Write-Host "video 2 frames: $video2_number_of_frames"

    return $video1_number_of_frames
}

function GenerateDiffs {
    param (
        [string]$work_dir,
        [int]$number_of_frames,
        [int]$num_cores,
        [int]$imagick_threads
    )

    Write-Host "generating diffs..."
    $t0 = Get-Date
    $frames_completed = [System.Collections.Concurrent.ConcurrentQueue[int]]::new()

    1..$number_of_frames | ForEach-Object -ThrottleLimit $num_cores -Parallel {
        $id = "{0:d6}" -f $_
        $frame = Join-Path -Path "${using:work_dir}" -ChildPath "${id}"
        magick -limit thread $using:imagick_threads "${frame}_a.png" "${frame}_b.png" -compose difference -composite -evaluate Pow 2 -evaluate divide 3 -separate -evaluate-sequence Add -evaluate Pow 0.5 "${frame}_c.png"
        magick -limit thread $using:imagick_threads "${frame}_c.png" -auto-level "${frame}_d.png"

        $q = $using:frames_completed
        $q.Enqueue(1)
        Write-Progress -Activity "generating diffs..." -Status "$($q.Count)/$using:number_of_frames frames completed" -PercentComplete (100 * $q.Count / $using:number_of_frames)
    }

    ShowDuration $t0
}

function RenderOutputVideo {
    param (
        [string]$work_dir,
        [string]$output_video
    )

    Write-Host "rendering output video..."

    $t0 = Get-Date
    ffmpeg -v error -framerate 60000/1001 -i "$work_dir\%06d_d.png" -c:v libx264 -crf 18 -preset veryfast "$output_video"
    ShowDuration $t0
}

function DeleteTempWorkDirectory {
    param (
        [string]$work_dir
    )

    Write-Host "cleaning up..."

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
ExtractFrames $work_dir $VIDEO1 $VIDEO2 $ffmpeg_threads
$number_of_frames = CountNumberOfFrames $work_dir
GenerateDiffs $work_dir $number_of_frames $num_cores $imagick_threads
RenderOutputVideo $work_dir $OUTPUT_VIDEO
DeleteTempWorkDirectory $work_dir
