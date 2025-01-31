#Requires –Version 7

<#
.SYNOPSIS
    Compare two videos frame by frame and generate a difference video.

.PARAMETER Video1
    The first video.

.PARAMETER Video2
    The second video.

.PARAMETER Output
    The name of the difference video.

.PARAMETER Montage
    (Optional) Filename of a montage video combining the two input videos and the diff.

.PARAMETER WorkDir
    (Optional) A working directory where all the temporary files will be created.
    Per default a temporary directory will be created and deleted afterwards.
    Setting this option implies "DontDeleteWorkDir".

.PARAMETER Jobs
    (Optional) Number of parallel jobs.
    Default: Number of logical CPU cores.

.PARAMETER FFmpegThreads
    (Optional) Number of FFmpeg threads when extracting frames.
    Default: Half the number of logical CPU cores.

.PARAMETER IMagickThreads
    (Optional) Number of threads for each ImageMagick process.
    Default: 2

.PARAMETER DontDeleteWorkDir
    Don't delete the working directory at the end of the script.
    This option is implied when manually setting "WorkDir".

.PARAMETER NoDiffVideo
    Don't render the difference video.

.PARAMETER NoMontageVideo
    Don't render the montage video.

.EXAMPLE
    & .\diff_video.ps1 -Video1 video1.mp4 -Video2 video2.mp4 -Output diff.mp4

    Compare video1.mp4 and video2.mp4 and generate a new difference video called diff.mp4.

.EXAMPLE
    & .\diff_video.ps1 video1.mp4 video2.mp4 diff.mp4

    Same as the previous example but without the named parameters.

.LINK
    https://github.com/Toxe/diff-video-ps1
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$Video1,
    [Parameter(Mandatory)] [string]$Video2,
    [Parameter(Mandatory)] [string]$Output,
    [string]$Montage,
    [string]$WorkDir,
    [int]$Jobs,
    [int]$FFmpegThreads,
    [int]$IMagickThreads,
    [switch]$DontDeleteWorkDir,
    [switch]$NoDiffVideo,
    [switch]$NoMontageVideo
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

        Write-Host ('  ({0:n3} seconds)' -f (((Get-Date) - $t).TotalSeconds)) -ForegroundColor Green
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

function FramerateToFPS {
    param (
        [string]$framerate
    )

    $a, $b = $framerate -split '/'
    return '{0:n2}' -f ($a / $b)
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
    return Join-Path -Path $temp_dir -ChildPath $random_name
}

function BuildFFmpegFramesFilenamePattern {
    param (
        [string]$dir,
        [string]$postfix
    )

    return Join-Path -Path $dir -ChildPath ('%06d_{0}.png' -f $postfix)
}

function BuildAllFramesGlob {
    param (
        [string]$dir,
        [string]$postfix
    )

    return Join-Path -Path $dir -ChildPath ('\*_{0}.png' -f $postfix)
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

    return Join-Path -Path $dir -ChildPath (& BuildFrameBasename $postfix $id)
}

function GetFrameCountFromVideo {
    param (
        [string]$video
    )

    return mediainfo --Inform='Video;%FrameCount%' $video
}

function CountExtractedFrames {
    param (
        [string]$work_dir,
        [string]$postfix
    )

    return (Get-ChildItem -Path $(BuildAllFramesGlob $work_dir $postfix) -Name -File).Count
}

function GetFileModificationTime {
    param (
        [string]$filename
    )

    return Get-ItemPropertyValue $filename -Name LastWriteTime

}

function UpdateFileModificationTime {
    param (
        [string]$filename,
        [datetime]$mtime
    )

    Set-ItemProperty $filename -Name LastWriteTime -Value $mtime
}

function UpdateModificationTimeForAllFrames {
    param (
        [string]$work_dir,
        [string]$postfix,
        [datetime]$mtime
    )

    Set-ItemProperty $(BuildAllFramesGlob $work_dir $postfix) -Name LastWriteTime -Value $mtime
}

function FileHasDifferentModificationTime {
    param (
        [string]$filename,
        [datetime]$mtime
    )

    return $mtime -ne (Get-ItemPropertyValue $filename -Name LastWriteTime)
}

function FilesHaveDifferentModificationTimes {
    param (
        [string]$filename1,
        [string]$filename2
    )

    return (Get-ItemPropertyValue $filename1 -Name LastWriteTime) -ne (Get-ItemPropertyValue $filename2 -Name LastWriteTime)
}

function AllFramesHaveModificationTime {
    param (
        [string]$work_dir,
        [string]$postfix,
        [datetime]$mtime
    )

    $files = Get-ChildItem -Path $(BuildAllFramesGlob $work_dir $postfix) -File
    return ($files | Where-Object { $_.LastWriteTime -ne $mtime }).Count -eq 0
}

function DeleteAllFrames {
    param (
        [string]$work_dir,
        [string]$postfix
    )

    Remove-Item -Path $(BuildAllFramesGlob $work_dir $postfix)
}

function FileIsMissing {
    param (
        [string]$filename
    )

    return -not (Test-Path $filename)
}

function InitializeParameters {
    if (-not $Script:Montage) {
        $Script:Montage = AddPostfixToFilename $Output 'montage'
    }

    if ($Script:WorkDir) {
        $Script:DontDeleteWorkDir = $true
    } else {
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
    Write-Host "  Jobs: $Jobs"
    Write-Host "  FFmpegThreads: $FFmpegThreads"
    Write-Host "  IMagickThreads: $IMagickThreads"
    Write-Host "  DontDeleteWorkDir: $DontDeleteWorkDir"
    Write-Host "  NoDiffVideo: $NoDiffVideo"
    Write-Host "  NoMontageVideo: $NoMontageVideo"
    Write-Host ''
}

function InputVideoMustExist {
    param (
        [string]$video,
        [int]$id
    )

    if (FileIsMissing $video) {
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

    if (FileIsMissing $work_dir) {
        New-Item -Path $work_dir -ItemType Directory | Out-Null
    }
}

function CheckVideoFramerates {
    param (
        [string]$video1,
        [string]$video2
    )

    WithDuration 'checking video framerates...' {
        $framerate1 = ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 -i $video1
        $framerate2 = ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 -i $video2
        $fps1 = FramerateToFPS $framerate1
        $fps2 = FramerateToFPS $framerate2

        Write-Host "  video 1: $fps1 FPS ($framerate1)"
        Write-Host "  video 2: $fps2 FPS ($framerate2)"

        if ($fps1 -ne $fps2) {
            Die 4 'The input videos must have the same framerate.'
        }

        return $framerate1
    }
}

function ExtractFrames {
    param (
        [string]$work_dir,
        [string]$video1,
        [string]$video2,
        [int]$ffmpeg_threads
    )

    WithDuration 'extracting frames...' {
        $func_AllFramesHaveModificationTime = ${function:AllFramesHaveModificationTime}.ToString()
        $func_BuildAllFramesGlob = ${function:BuildAllFramesGlob}.ToString()
        $func_BuildFramesFilenameTemplate = ${function:BuildFFmpegFramesFilenamePattern}.ToString()
        $func_CountExtractedFrames = ${function:CountExtractedFrames}.ToString()
        $func_DeleteAllFrames = ${function:DeleteAllFrames}.ToString()
        $func_GetFileModificationTime = ${function:GetFileModificationTime}.ToString()
        $func_GetFrameCountFromVideo = ${function:GetFrameCountFromVideo}.ToString()
        $func_UpdateModificationTimeForAllFrames = ${function:UpdateModificationTimeForAllFrames}.ToString()

        $videos = @(
            @(1, $video1, 'a'),
            @(2, $video2, 'b')
        )

        $videos | ForEach-Object -Parallel {
            ${function:AllFramesHaveModificationTime} = $using:func_AllFramesHaveModificationTime
            ${function:BuildAllFramesGlob} = $using:func_BuildAllFramesGlob
            ${function:BuildFFmpegFramesFilenamePattern} = $using:func_BuildFramesFilenameTemplate
            ${function:CountExtractedFrames} = $using:func_CountExtractedFrames
            ${function:DeleteAllFrames} = $using:func_DeleteAllFrames
            ${function:GetFileModificationTime} = $using:func_GetFileModificationTime
            ${function:GetFrameCountFromVideo} = $using:func_GetFrameCountFromVideo
            ${function:UpdateModificationTimeForAllFrames} = $using:func_UpdateModificationTimeForAllFrames

            $id = $_[0]
            $video = $_[1]
            $postfix = $_[2]

            $frame_count_from_video = GetFrameCountFromVideo $video
            $number_of_existing_frames = CountExtractedFrames ${using:work_dir} $postfix
            $mtime = GetFileModificationTime $video

            # only extract frames if either some frame files are missing or the modification time of at least one file is outdated
            if (($frame_count_from_video -ne $number_of_existing_frames) -or (-not (AllFramesHaveModificationTime ${using:work_dir} $postfix $mtime))) {
                Write-Host "  video ${id}: extracting $frame_count_from_video frames"

                # delete all existing frames
                DeleteAllFrames ${using:work_dir} $postfix

                # extract video frames
                $frames = BuildFFmpegFramesFilenamePattern ${using:work_dir} $postfix
                ffmpeg -v error -i $video -threads $using:ffmpeg_threads $frames

                # set modification time of all extracted frames to the one of their corresponding video
                UpdateModificationTimeForAllFrames ${using:work_dir} $postfix $mtime
            } else {
                Write-Host "  video ${id}: no need to extract frames again"
            }
        }

        # count number of extracted frames
        $video1_number_of_frames = CountExtractedFrames $work_dir 'a'
        $video2_number_of_frames = CountExtractedFrames $work_dir 'b'
        Write-Host "  video 1 frames: $video1_number_of_frames"
        Write-Host "  video 2 frames: $video2_number_of_frames"

        $offset = [math]::Abs($video1_number_of_frames - $video2_number_of_frames)

        if ($offset -ne 0) {
            # The videos have different numbers of frames, so remove the excess frames. If the difference is for example 23:
            # - delete frames 1 to 23
            # - rename frame 24 to 1, 25 to 2 etc.
            Write-Warning "The input videos don't have the same number of frames!"

            $num_frames = [math]::Max($video1_number_of_frames, $video2_number_of_frames)
            $postfix = if ($video1_number_of_frames -gt $video2_number_of_frames) { 'a' } else { 'b' }

            for ($i = 1; $i -le $num_frames; ++$i) {
                $frame = BuildFrameFullPath $work_dir $postfix $i

                if ($i -gt $offset) {
                    Rename-Item -Path $frame -NewName "$(BuildFrameBasename $postfix ($i - $offset))"
                } else {
                    Remove-Item -Path $frame
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
        $func_FileHasDifferentModificationTime = ${function:FileHasDifferentModificationTime}.ToString()
        $func_FileIsMissing = ${function:FileIsMissing}.ToString()
        $func_GetFileModificationTime = ${function:GetFileModificationTime}.ToString()
        $func_UpdateFileModificationTime = ${function:UpdateFileModificationTime}.ToString()

        $generated_frames = 1..$number_of_frames | ForEach-Object -ThrottleLimit $num_cores -Parallel {
            ${function:BuildFrameBasename} = $using:func_BuildFrameBasename
            ${function:BuildFrameFullPath} = $using:func_BuildFrameFullPath
            ${function:FileHasDifferentModificationTime} = $using:func_FileHasDifferentModificationTime
            ${function:FileIsMissing} = $using:func_FileIsMissing
            ${function:GetFileModificationTime} = $using:func_GetFileModificationTime
            ${function:UpdateFileModificationTime} = $using:func_UpdateFileModificationTime

            $frame_a = BuildFrameFullPath ${using:work_dir} 'a' $_
            $frame_b = BuildFrameFullPath ${using:work_dir} 'b' $_
            $frame_d = BuildFrameFullPath ${using:work_dir} 'd' $_

            # determine the latest modification time between frames a and b
            $mtime_a = GetFileModificationTime $frame_a
            $mtime_b = GetFileModificationTime $frame_b
            $mtime = [DateTime][math]::Max($mtime_a.Ticks, $mtime_b.Ticks)

            # only create diff if it either doesn't exist or its modification time doesn't match $mtime
            $generated = $false

            if ((FileIsMissing $frame_d) -or (FileHasDifferentModificationTime $frame_d $mtime)) {
                magick -limit thread $using:imagick_threads $frame_a $frame_b -compose difference -composite -evaluate Pow 2 -evaluate divide 3 -separate -evaluate-sequence Add -evaluate Pow 0.5 $frame_d

                # update modification time of the diff to the latest time
                UpdateFileModificationTime $frame_d $mtime
                $generated = $true
            }

            ConvertTo-Json -Compress $_, $generated
        } | WithProgress -Activity 'generating diffs...' -MaxCounter $number_of_frames -Process {
            $counter, $generated = ConvertFrom-Json $_

            if ($generated) {
                $counter
            }
        }

        if ($generated_frames.Count -eq 0) {
            Write-Host '  no diffs needed to be generated'
        } else {
            Write-Host "  generated $($generated_frames.Count) diffs"
        }
    }
}

function CheckIfDiffsNeedToBeNormalized {
    param (
        [string]$work_dir,
        [int]$number_of_frames,
        [int]$num_cores
    )

    WithDuration 'checking if diffs need to be normalized...' {
        $normalization_needed = $false

        if ($number_of_frames -eq (CountExtractedFrames $work_dir 'n')) {
            foreach ($i in 1..$number_of_frames) {
                if (FilesHaveDifferentModificationTimes $(BuildFrameFullPath $work_dir 'd' $i) (BuildFrameFullPath $work_dir 'n' $i)) {
                    $normalization_needed = $true
                    break
                }
            }
        } else {
            $normalization_needed = $true
        }

        if ($normalization_needed) {
            Write-Host '  diffs need to be normalized'
        } else {
            Write-Host "  diffs don't need to be normalized"
        }

        return $normalization_needed
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

            $frame = BuildFrameFullPath ${using:work_dir} 'd' $_
            $output = magick identify -limit thread $using:imagick_threads -format '%[min] %[max]\n' $frame
            $output
        } | WithProgress -Activity 'calculating min/max intensity...' -MaxCounter $number_of_frames -Process { $_ }

        $min_intensity = [int]::MaxValue
        $max_intensity = [int]::MinValue

        $lines | ForEach-Object {
            $a, $b = $_ -split ' '
            $min_intensity = [math]::min($a, $min_intensity)
            $max_intensity = [math]::max($b, $max_intensity)
        }

        Write-Host "  min intensity: $min_intensity"
        Write-Host "  max intensity: $max_intensity"

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
        $func_GetFileModificationTime = ${function:GetFileModificationTime}.ToString()
        $func_UpdateFileModificationTime = ${function:UpdateFileModificationTime}.ToString()

        1..$number_of_frames | ForEach-Object -ThrottleLimit $num_cores -Parallel {
            ${function:BuildFrameBasename} = $using:func_BuildFrameBasename
            ${function:BuildFrameFullPath} = $using:func_BuildFrameFullPath
            ${function:GetFileModificationTime} = $using:func_GetFileModificationTime
            ${function:UpdateFileModificationTime} = $using:func_UpdateFileModificationTime

            $frame_d = BuildFrameFullPath ${using:work_dir} 'd' $_
            $frame_n = BuildFrameFullPath ${using:work_dir} 'n' $_
            $mtime = GetFileModificationTime $frame_d

            magick -limit thread $using:imagick_threads $frame_d -level "$using:min_intensity,$using:max_intensity" $frame_n
            UpdateFileModificationTime $frame_n $mtime

            $_
        } | WithProgress -Activity 'normalizing diffs...' -MaxCounter $number_of_frames
    }
}

function RenderWithFFmpeg {
    param (
        [string]$activity,
        [int]$number_of_frames,
        [ScriptBlock]$ffmpeg
    )

    WithDuration $activity {
        & $ffmpeg |
            Where-Object { $_ -match 'frame=(\d+)' } |
            ForEach-Object { $Matches[1] } |
            WithProgress -Activity $activity -MaxCounter $number_of_frames -StatusText 'frames' -UpdateCounter { $_ }
    }
}

function RenderVideoDiff {
    param (
        [string]$work_dir,
        [string]$output_video_diff,
        [int]$number_of_frames,
        [string]$framerate
    )

    RenderWithFFmpeg 'rendering diff video...' $number_of_frames {
        $frames_n = BuildFFmpegFramesFilenamePattern $work_dir 'n'
        ffmpeg -v error -nostats -hide_banner -progress pipe:1 -framerate $framerate -i $frames_n -vf 'colorchannelmixer=.0:.0:.0:0:.0:1:.0:0:.0:.0:.0:0' -c:v libx264 -crf 18 -preset veryfast $output_video_diff
    }
}

function RenderVideoMontage {
    param (
        [string]$work_dir,
        [string]$output_video_montage,
        [int]$number_of_frames,
        [string]$framerate
    )

    RenderWithFFmpeg 'rendering montage video...' $number_of_frames {
        $frames_a = BuildFFmpegFramesFilenamePattern $work_dir 'a'
        $frames_b = BuildFFmpegFramesFilenamePattern $work_dir 'b'
        $frames_n = BuildFFmpegFramesFilenamePattern $work_dir 'n'
        ffmpeg -v error -nostats -hide_banner -progress pipe:1 -framerate $framerate -i $frames_a -framerate $framerate -i $frames_b -framerate $framerate -i $frames_n -filter_complex '[0:v][1:v]vstack[left]; [2:v]colorchannelmixer=.0:.0:.0:0:.0:1:.0:0:.0:.0:.0:0[v2]; [v2]pad=iw:2*ih:0:ih/2:black[right]; [left][right]hstack' -c:v libx264 -crf 18 -preset veryfast $output_video_montage
    }
}

function RenderDiffAndMontageVideosSimultaneously {
    param (
        [string]$work_dir,
        [string]$output_video_diff,
        [string]$output_video_montage,
        [int]$number_of_frames,
        [string]$framerate
    )

    RenderWithFFmpeg 'rendering diff and montage video simultaneously...' $number_of_frames {
        $frames_a = BuildFFmpegFramesFilenamePattern $work_dir 'a'
        $frames_b = BuildFFmpegFramesFilenamePattern $work_dir 'b'
        $frames_n = BuildFFmpegFramesFilenamePattern $work_dir 'n'
        ffmpeg -v error -nostats -hide_banner -progress pipe:1 -framerate $framerate -i $frames_a -framerate $framerate -i $frames_b -framerate $framerate -i $frames_n -filter_complex '[0:v][1:v]vstack[left]; [2:v]colorchannelmixer=.0:.0:.0:0:.0:1:.0:0:.0:.0:.0:0[v2]; [v2]split[diff][out1]; [diff]pad=iw:2*ih:0:ih/2:black[right]; [left][right]hstack[out2]' -map '[out1]' -c:v libx264 -crf 18 -preset veryfast $output_video_diff -map '[out2]' -c:v libx264 -crf 18 -preset veryfast $output_video_montage
    }
}

function DeleteWorkDirectory {
    param (
        [string]$work_dir
    )

    WithDuration 'deleting work directory...' {
        Remove-Item -Path $work_dir -Recurse
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

    $framerate = CheckVideoFramerates $Video1 $Video2
    CreateWorkDirectory $WorkDir
    $number_of_frames = ExtractFrames $WorkDir $Video1 $Video2 $FFmpegThreads
    GenerateDiffs $WorkDir $number_of_frames $Jobs $IMagickThreads

    if (CheckIfDiffsNeedToBeNormalized $WorkDir $number_of_frames $Jobs) {
        $min_intensity, $max_intensity = CalculateMinMaxIntensity $WorkDir $number_of_frames $Jobs $IMagickThreads
        NormalizeDiffs $WorkDir $number_of_frames $Jobs $IMagickThreads $min_intensity $max_intensity
    }

    # render both videos simultaneously if possible
    if ((-not $NoDiffVideo) -and (-not $NoMontageVideo)) {
        RenderDiffAndMontageVideosSimultaneously $WorkDir $Output $Montage $number_of_frames $framerate
    } else {
        if (-not $NoDiffVideo) {
            RenderVideoDiff $WorkDir $Output $number_of_frames $framerate
        }

        if (-not $NoMontageVideo) {
            RenderVideoMontage $WorkDir $Montage $number_of_frames $framerate
        }
    }

    if (-not $DontDeleteWorkDir) {
        DeleteWorkDirectory $WorkDir
    }
}

Main
