# & .\diff_video.ps1 video1 video2 output.mp4

[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$Video1,
    [Parameter(Mandatory)] [string]$Video2,
    [Parameter(Mandatory)] [string]$Output,
    [string]$Montage,
    [string]$WorkDir,
    [switch]$DontDeleteWorkDir,
    [int]$Jobs,
    [int]$FFmpegThreads,
    [int]$IMagickThreads
)

function WithDuration {
    param (
        [string]$label,
        [ScriptBlock]$command
    )

    process {
        Write-Host $label
        $t = Get-Date

        & $command

        Write-Host ('--> {0:n3} seconds' -f (((Get-Date) - $t).TotalSeconds))
        Write-Host ''
    }
}

function WithProgress {
    param (
        [Parameter(ValueFromPipeline)] $pipeline_input,
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

        & $Process $pipeline_input

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

function AddPostfixToFilename {
    param (
        [string]$filename,
        [string]$postfix
    )

    $dir = [System.IO.Path]::GetDirectoryName($filename)
    $basename = [System.IO.Path]::GetFileNameWithoutExtension($filename)
    $extension = [System.IO.Path]::GetExtension($filename)
    return [System.IO.Path]::Combine($dir, '{0}_{1}{2}' -f ($basename, $postfix, $extension))
}

function BuildWorkDirName {
    $temp_dir = [System.IO.Path]::GetTempPath()
    $random_name = [System.IO.Path]::GetRandomFileName()
    return Join-Path -Path "$temp_dir" -ChildPath "$random_name"
}

function BuildFramesFilenameTemplate {
    param (
        [string]$dir,
        [string]$postfix
    )

    return '{0}\%06d_{1}.png' -f ($dir, $postfix)
}

function BuildFrameBasename {
    param (
        [string]$postfix,
        [int]$id
    )

    return '{0:d6}_{1}.png' -f ($id, $postfix)
}

function BuildFrameFullPath {
    param (
        [string]$dir,
        [string]$postfix,
        [int]$id
    )

    return Join-Path -Path "$dir" -ChildPath (& BuildFrameBasename $postfix $id)
}

function InitializeParameters {
    if (-not $Script:Montage) {
        $Script:Montage = AddPostfixToFilename $Output 'montage'
    }

    if (-not $Script:WorkDir) {
        $Script:WorkDir = BuildWorkDirName
    }

    if ($Script:Jobs -le 0) {
        $Script:Jobs = [Environment]::ProcessorCount
    }

    if ($Script:FFmpegThreads -le 0) {
        $Script:FFmpegThreads = [int]([Environment]::ProcessorCount / 2)
    }

    if ($Script:IMagickThreads -le 0) {
        $Script:IMagickThreads = 2
    }

    Write-Host 'Parameters:'
    Write-Host "  Video1: $Video1"
    Write-Host "  Video2: $Video2"
    Write-Host "  Output: $Output"
    Write-Host "  Montage: $Montage"
    Write-Host "  WorkDir: $WorkDir"
    Write-Host "  DontDeleteWorkDir: $DontDeleteWorkDir"
    Write-Host "  Jobs: $Jobs"
    Write-Host "  FFmpegThreads: $FFmpegThreads"
    Write-Host "  IMagickThreads: $IMagickThreads"
}

function InputVideoMustExist {
    param (
        [string]$video,
        [int]$id
    )

    if (-Not (Test-Path $video)) {
        Die 1 "Video $id not found: $video"
    }
}

function OutputVideoMustNotExist {
    param (
        [string]$video,
        [string]$desc
    )

    if (Test-Path $video) {
        Die 2 "Output video ($desc) already exists: $video"
    }
}

function OutputVideoMustBeMP4 {
    param (
        [string]$video,
        [string]$desc
    )

    if ([System.IO.Path]::GetExtension($video) -ne '.mp4') {
        Die 3 "Output video ($desc) must be an '.mp4' file: $video"
    }
}

function CreateWorkDirectory {
    param (
        [string]$work_dir
    )

    if ( -not (Test-Path "$work_dir") ) {
        New-Item -Path "$work_dir" -ItemType Directory | Out-Null
    }
}

function ExtractFrames {
    param (
        [string]$work_dir,
        [string]$video1,
        [string]$video2,
        [int]$ffmpeg_threads
    )

    Write-Host ''

    WithDuration 'extracting frames...' {
        $func_BuildFramesFilenameTemplate = ${function:BuildFramesFilenameTemplate}.ToString()

        $videos = @(
            @($video1, 'a'),
            @($video2, 'b')
        )

        $videos | ForEach-Object -Parallel {
            ${function:BuildFramesFilenameTemplate} = $using:func_BuildFramesFilenameTemplate

            $video = $_[0]
            $frames = BuildFramesFilenameTemplate "${using:work_dir}" $_[1]
            ffmpeg -v error -i "$video" -threads $using:ffmpeg_threads "$frames"
        }

        $video1_number_of_frames = (Get-ChildItem -Path "$work_dir" -Name -File -Filter *_a.png).Length
        $video2_number_of_frames = (Get-ChildItem -Path "$work_dir" -Name -File -Filter *_b.png).Length
        Write-Host "video 1 frames: $video1_number_of_frames"
        Write-Host "video 2 frames: $video2_number_of_frames"

        $offset = [math]::Abs($video1_number_of_frames - $video2_number_of_frames)

        if ($offset -ne 0) {
            # The videos have different numbers of frames, so remove the excess frames. If the difference is for example 23:
            # - delete frames 1 to 23
            # - rename frame 24 to 1, 25 to 2 etc.
            Write-Warning "The input videos don't have the same number of frames!"

            $num_frames = [math]::Max($video1_number_of_frames, $video2_number_of_frames)
            $postfix = if ($video1_number_of_frames -gt $video2_number_of_frames) { 'a' } else { 'b' }

            for ($i = 1; $i -le $num_frames; ++$i) {
                $frame = BuildFrameFullPath "$work_dir" $postfix $i

                if ($i -gt $offset) {
                    Rename-Item -Path "$frame" -NewName "$(BuildFrameBasename $postfix ($i - $offset))"
                } else {
                    Remove-Item -Path "$frame"
                }
            }
        }

        return [math]::Min($video1_number_of_frames, $video2_number_of_frames)
    }
}

function GenerateDiffs {
    param (
        [string]$work_dir,
        [int]$number_of_frames,
        [int]$num_cores,
        [int]$imagick_threads
    )

    WithDuration 'generating diffs...' {
        $func_BuildFrameBasename = ${function:BuildFrameBasename}.ToString()
        $func_BuildFrameFullPath = ${function:BuildFrameFullPath}.ToString()

        1..$number_of_frames | ForEach-Object -ThrottleLimit $num_cores -Parallel {
            ${function:BuildFrameBasename} = $using:func_BuildFrameBasename
            ${function:BuildFrameFullPath} = $using:func_BuildFrameFullPath

            $frame_a = BuildFrameFullPath "${using:work_dir}" 'a' $_
            $frame_b = BuildFrameFullPath "${using:work_dir}" 'b' $_
            $frame_d = BuildFrameFullPath "${using:work_dir}" 'd' $_
            magick -limit thread $using:imagick_threads "${frame_a}" "${frame_b}" -compose difference -composite -evaluate Pow 2 -evaluate divide 3 -separate -evaluate-sequence Add -evaluate Pow 0.5 "${frame_d}"
            $_
        } | WithProgress -Activity 'generating diffs...' -MaxCounter $number_of_frames
    }
}

function CalculateMinMaxIntensity {
    param (
        [string]$work_dir,
        [int]$number_of_frames,
        [int]$num_cores,
        [int]$imagick_threads
    )

    WithDuration 'calculating min/max intensity...' {
        $func_BuildFrameBasename = ${function:BuildFrameBasename}.ToString()
        $func_BuildFrameFullPath = ${function:BuildFrameFullPath}.ToString()

        $lines = 1..$number_of_frames | ForEach-Object -ThrottleLimit $num_cores -Parallel {
            ${function:BuildFrameBasename} = $using:func_BuildFrameBasename
            ${function:BuildFrameFullPath} = $using:func_BuildFrameFullPath

            $frame = BuildFrameFullPath "${using:work_dir}" 'd' $_
            $output = magick identify -limit thread $using:imagick_threads -format '%[min] %[max]\n' "${frame}"
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

        return $min_intensity, $max_intensity
    }
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

    WithDuration 'normalizing diffs...' {
        $func_BuildFrameBasename = ${function:BuildFrameBasename}.ToString()
        $func_BuildFrameFullPath = ${function:BuildFrameFullPath}.ToString()

        1..$number_of_frames | ForEach-Object -ThrottleLimit $num_cores -Parallel {
            ${function:BuildFrameBasename} = $using:func_BuildFrameBasename
            ${function:BuildFrameFullPath} = $using:func_BuildFrameFullPath

            $frame_d = BuildFrameFullPath "${using:work_dir}" 'd' $_
            $frame_n = BuildFrameFullPath "${using:work_dir}" 'n' $_
            magick -limit thread $using:imagick_threads "${frame_d}" -level "$using:min_intensity,$using:max_intensity" "${frame_n}"
            $_
        } | WithProgress -Activity 'normalizing diffs...' -MaxCounter $number_of_frames
    }
}

function RenderVideoDiff {
    param (
        [string]$work_dir,
        [string]$output_video_diff,
        [int]$number_of_frames
    )

    WithDuration 'rendering diff video...' {
        $frames_n = BuildFramesFilenameTemplate "$work_dir" 'n'

        ffmpeg -v error -nostats -hide_banner -progress pipe:1 -framerate 60000/1001 -i "$frames_n" -vf 'colorchannelmixer=.0:.0:.0:0:.0:1:.0:0:.0:.0:.0:0' -c:v libx264 -crf 18 -preset veryfast "$output_video_diff" |
            Where-Object { $_ -match 'frame=(\d+)' } |
            ForEach-Object { $Matches[1] } |
            WithProgress -Activity 'rendering diff video...' -MaxCounter $number_of_frames -StatusText 'frames' -UpdateCounter { $_ }
    }
}

function RenderVideoMontage {
    param (
        [string]$work_dir,
        [string]$output_video_montage,
        [int]$number_of_frames
    )

    WithDuration 'rendering montage video...' {
        $frames_a = BuildFramesFilenameTemplate "$work_dir" 'a'
        $frames_b = BuildFramesFilenameTemplate "$work_dir" 'b'
        $frames_n = BuildFramesFilenameTemplate "$work_dir" 'n'

        ffmpeg -v error -nostats -hide_banner -progress pipe:1 -framerate 60000/1001 -i "$frames_a" -framerate 60000/1001 -i "$frames_b" -framerate 60000/1001 -i "$frames_n" -filter_complex '[0:v][1:v]vstack[left]; [2:v]colorchannelmixer=.0:.0:.0:0:.0:1:.0:0:.0:.0:.0:0[v2]; [v2]pad=iw:2*ih:0:ih/2:black[right]; [left][right]hstack' -c:v libx264 -crf 18 -preset veryfast "$output_video_montage" |
            Where-Object { $_ -match 'frame=(\d+)' } |
            ForEach-Object { $Matches[1] } |
            WithProgress -Activity 'rendering montage video...' -MaxCounter $number_of_frames -StatusText 'frames' -UpdateCounter { $_ }
    }
}

function DeleteWorkDirectory {
    param (
        [string]$work_dir
    )

    WithDuration 'deleting work directory...' {
        Remove-Item -Path "$work_dir" -Recurse
    }
}

function Main {
    $PSStyle.Progress.View = 'Classic'

    InitializeParameters
    InputVideoMustExist $Video1 1
    InputVideoMustExist $Video2 2
    OutputVideoMustNotExist $Output 'diff'
    OutputVideoMustNotExist $Montage 'montage'
    OutputVideoMustBeMP4 $Output 'diff'
    OutputVideoMustBeMP4 $Montage 'montage'

    CreateWorkDirectory $WorkDir
    $number_of_frames = ExtractFrames $WorkDir $Video1 $Video2 $FFmpegThreads
    GenerateDiffs $WorkDir $number_of_frames $Jobs $IMagickThreads
    $min_intensity, $max_intensity = CalculateMinMaxIntensity $WorkDir $number_of_frames $Jobs $IMagickThreads
    NormalizeDiffs $WorkDir $number_of_frames $Jobs $IMagickThreads $min_intensity $max_intensity
    RenderVideoDiff $WorkDir $Output $number_of_frames
    RenderVideoMontage $WorkDir $Montage $number_of_frames

    if (-not $DontDeleteWorkDir) {
        DeleteWorkDirectory $WorkDir
    }
}

Main
