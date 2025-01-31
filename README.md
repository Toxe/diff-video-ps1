# Diff-Video PowerShell Script

Compare two videos frame by frame and generate a difference video and a montage video of the input and diff videos side by side.

> Note: While PowerShell is also available for Linux and macOS I only tested this on Windows.

## Dependencies

- PowerShell 7 or greater
- [FFmpeg](https://ffmpeg.org)
- [ImageMagick](https://imagemagick.org)
- [MediaInfo](https://mediaarea.net/en/MediaInfo)

## Example

The following commands are all equivalent and will create two files: `diff.mp4` and `diff_montage.mp4`.

```powershell
PS> & .\diff_video.ps1 .\video1.mp4 .\video2.webm diff.mp4
PS> & .\diff_video.ps1 -Video1 .\video1.mp4 -Video2 .\video2.webm -Output diff.mp4
PS> & .\diff_video.ps1 -Video1 .\video1.mp4 -Video2 .\video2.webm -Output diff.mp4 -Montage diff_montage.mp4
```

```
Parameters:
  Video1: .\video1.mp4
  Video2: .\video2.webm
  Output: diff.mp4
  Montage: diff_montage.mp4
  WorkDir: C:\Users\toxe\AppData\Local\Temp\cehzzfjr.e3r
  Jobs: 24
  FFmpegThreads: 12
  IMagickThreads: 2
  DontDeleteWorkDir: False
  NoDiffVideo: False
  NoMontageVideo: False

checking video framerates...
  video 1: 59.94 FPS (60000/1001)
  video 2: 59.94 FPS (19001/317)
  (0.210 seconds)

extracting frames...
  video 1: extracting 1224 frames
  video 2: extracting 1224 frames
  video 1 frames: 1224
  video 2 frames: 1224
  (26.665 seconds)

generating diffs...
  generated 1224 diffs
  (92.923 seconds)

checking if diffs need to be normalized...
  diffs need to be normalized
  (0.010 seconds)

calculating min/max intensity...
  min intensity: 0
  max intensity: 39321
  (10.843 seconds)

normalizing diffs...
  (40.849 seconds)

rendering diff and montage video simultaneously...
  (43.352 seconds)

deleting work directory...
  (1.932 seconds)
```

## Help

```powershell
PS> Get-Help .\diff_video.ps1 -Detailed
```

```
NAME
    diff_video.ps1

SYNOPSIS
    Compare two videos frame by frame and generate a difference video.


SYNTAX
    diff_video.ps1 [-Video1] <String> [-Video2] <String> [-Output] <String> [[-Montage] <String>]
    [[-WorkDir] <String>] [[-Jobs] <Int32>] [[-FFmpegThreads] <Int32>] [[-IMagickThreads] <Int32>]
    [-DontDeleteWorkDir] [-NoDiffVideo] [-NoMontageVideo] [<CommonParameters>]


PARAMETERS
    -Video1 <String>
        The first video.

    -Video2 <String>
        The second video.

    -Output <String>
        The name of the difference video.

    -Montage <String>
        (Optional) Filename of a montage video combining the two input videos and the diff.

    -WorkDir <String>
        (Optional) A working directory where all the temporary files will be created.
        Per default a temporary directory will be created and deleted afterwards.
        Setting this option implies "DontDeleteWorkDir".

    -Jobs <Int32>
        (Optional) Number of parallel jobs.
        Default: Number of logical CPU cores.

    -FFmpegThreads <Int32>
        (Optional) Number of FFmpeg threads when extracting frames.
        Default: Half the number of logical CPU cores.

    -IMagickThreads <Int32>
        (Optional) Number of threads for each ImageMagick process.
        Default: 2

    -DontDeleteWorkDir [<SwitchParameter>]
        Don't delete the working directory at the end of the script.
        This option is implied when manually setting "WorkDir".

    -NoDiffVideo [<SwitchParameter>]
        Don't render the difference video.

    -NoMontageVideo [<SwitchParameter>]
        Don't render the montage video.

    <CommonParameters>
        This cmdlet supports the common parameters: Verbose, Debug,
        ErrorAction, ErrorVariable, WarningAction, WarningVariable,
        OutBuffer, PipelineVariable, and OutVariable. For more information, see
        about_CommonParameters (https://go.microsoft.com/fwlink/?LinkID=113216).

    -------------------------- EXAMPLE 1 --------------------------

    PS > & .\diff_video.ps1 -Video1 video1.mp4 -Video2 video2.mp4 -Output diff.mp4

    Compare video1.mp4 and video2.mp4 and generate a new difference video called diff.mp4.




    -------------------------- EXAMPLE 2 --------------------------

    PS > & .\diff_video.ps1 video1.mp4 video2.mp4 diff.mp4

    Same as the previous example but without the named parameters.




REMARKS
    To see the examples, type: "Get-Help .\diff_video.ps1 -Examples"
    For more information, type: "Get-Help .\diff_video.ps1 -Detailed"
    For technical information, type: "Get-Help .\diff_video.ps1 -Full"
    For online help, type: "Get-Help .\diff_video.ps1 -Online"
```
