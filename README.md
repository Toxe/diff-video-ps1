# Diff-Video PowerShell Script

Compare two videos frame by frame and generate a difference video.

## Dependencies

- PowerShell 7+
- [FFmpeg](https://ffmpeg.org)
- [ImageMagick](https://imagemagick.org)
- [MediaInfo](https://mediaarea.net/en/MediaInfo)

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
