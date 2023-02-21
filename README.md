# xObsAsyncImageSource
OBS plugin providing an image source that loads images asynchronously (causing a lot less lag on load).

![image](https://user-images.githubusercontent.com/528974/220008779-3075b81d-0883-4038-970c-f84a432cc54e.png)

## Prerequisites
- OBS 29+ 64 bit
- Currently only working on Windows (tested only on Windows 10, but Windows 11 should also work)

## Comparison to original image source

### Less lag and dropped frames
The original image source can cause short freezes of OBS (aka lags) when loading images, to be more precise it will often make OBS drop frames and cause the counter
"Frames missed due to rendering lag" to increase, you can view this statistic in the window shown by selecting "View" and "Stats" from the OBS main window.

The async image source will be a lot less likely to cause this.

### Loading behavior
While the async image source is still busy loading an image it simply keeps on showing whatever it was showing previously.

If it was hidden or didn't have any image file configured (or an invalid/missing file) it will show nothing, if it was showing a different image
then it will keep on showing this image until it finished loading the new image.

This behavior will ensure a smooth transition from one image to another (as opposed to causing flickering if the old image would always be hidden while loading a new one).

If another image load is already triggered while the previous image load wasn't finished the previous load will be aborted in favor of the new one.

If loading fails the async image source will keep on trying to load the image every second. This way if the file was locked during the last load attempt (e.g. happens when it is updated at the exact time the image source tries to read the file) it will be updated a second later (whereas the original image source [would never recover from this until the image file is updated once more](https://github.com/obsproject/obs-studio/issues/3275)).

### Usage scenarios
You should prefer this image source over the original one whenever images are not only (re-)loaded once on startup of OBS but also during runtime. This is the case when:

- you have "Unload image when not showing" activated on one or more images and hide/show these images during a session
- image files shown by an image source change during a session
- you sometimes add new image sources during a session
- you sometimes open the properties of image sources during a session (changing nothing and clicking cancel triggers a reload)

If you only use images that were loaded at startup and are either visible all the time or have "Unload image when not showing" unchecked if you hide/show
them throughout a session this async source doesn't give you any benefits. Well, almost. Even during initial load with OBS startup the original image
source can cause unnecessary audio buffering increases (the infamous "adding X milliseconds of audio buffering" in your log) while the async image
source is a lot less likely to trigger this.

### Technical background
The original image source loads images on the main thread, blocking all rendering in OBS while it is busy loading the image.
30 FPS mean that OBS has ((1 / 30) * 1000 =) 33,33... ms time to render each frame, with 60 FPS this drops to 16,66... ms and so on.
In my tests loading even relatively small images took anything from 40 to 80 ms, an animated image even 200+ ms.

This means that while loading an image OBS will almost certainly have to drop frames because it cannot render them on time. Combine this with
the fact that OBS doesn't react well to rendering lag and [you're in trouble](https://github.com/obsproject/obs-studio/issues/6673),
even more so if you use secondary outputs like NDI or Teleport. When reporting OBS problems caused by lag the first advice you will get
is most probably that you should eliminate the source of the lag. This advice of course is correct, but what do you do if it's caused by loading
images that you need to be loaded?

This async image source uses exactly the same OBS internal loading/decoding/rendering functions for the images (in fact large chunks
of the code are a 1:1 copy of the original image source code), with the one difference that the functions which take the most time during loading an image
are executed asynchronously on a separate thread instead of the main OBS thread. Also working multi-threaded introduces some complexity, i.e. extra code
to eventually synchronize things back to the main thread after loading was finished.

## Usage
After installation add a source just like you would [add the original image source](https://obsproject.com/wiki/Sources-Guide#image), but instead select "Image (Async)" from the list of available source types.

![image](https://user-images.githubusercontent.com/528974/220010613-2cb22305-45d0-4bcb-b613-c8a01306ad10.png)

Configuration is exactly the same as for the original image source.

### Convert all existing image sources
If you want to convert all your existing standard image sources to async image sources at once
- close OBS in case it is running
- make a backup of your scenes .json file
- open your scenes .json file in a text editor and replace all occurrences of "image_source" with "xObsAsyncImageSource" (in both cases including the quotes)
- start OBS and your image sources should have been converted
To verify whether the conversion was actually applied click the plus icon to add a new source, select "Image (Async)" and check the list under "Add Existing", it should list your existing image sources.

## FAQ
- **Q**: Will my OBS completely stop dropping frames when loading images with this source?
  - **A**: Under ideal conditions yes, but that depends a lot on your system and configuration. If your computer is already maxing out its CPU usage even before the image load and/or you load a really large image you could still get lags/dropped frames, albeit a lot less compared to the original image source. E.g. in my tests when running OBS at 60 FPS and loading an unusually complex and big 5000x5000 .png file the original source would drop ~50 frames while the async image source would drop 5.

- **Q**: Wow, that's cool, can I also have this for image slide show sources?
  - **A**: My motiviation to do this is rather low, since this would be more complex and I currently don't use the slide show source myself. There is already [a pull request to improve the original OBS source](https://github.com/obsproject/rfcs/pull/17), so it would make more sense to wait for this to be implemented. You could of course compile this yourself or try to contact the author and ask whether they would want to release this as a separate plugin.

- **Q**: Why is the plugin file so big compared to other plugins for the little bit it does, will this cause issues?
  - **A**: Unlike other plugins it's not written directly in C++ but in C# using .NET 7 and NativeAOT (for more details read on in the section for developers). This produces some overhead in the actual plugin file, however, the code that matters for functionality of this plugin should be just as efficient and fast as code directly written in C++ so there's no reason to worry about performance on your system.

- **Q**: Will there be a version for other operating systems, e.g. Linux?
  - **A**: NativeAOT only supports compiling for Windows targets when running on Windows and Linux targets when running on Linux, see [here](https://github.com/dotnet/runtime/blob/main/src/coreclr/nativeaot/docs/compiling.md#cross-architecture-compilation). I only use Windows myself so in order to be able to compile for Linux I'd need to set up a Linux VM first. I will probably do that at some point in the future but it doesn't have the highest priority. Feel free to try it yourself, will happily integrate contributions (e.g. information, pull requests and binaries) in this direction.

- **Q**: Will there be a 32 bit version of this plugin?
  - **A**: No. Feel free to try and compile it for x86 targets yourself, last time I checked it wasn't fully supported in NativeAOT.


## For developers
### C#
OBS Classic still had a [CLR Host Plugin](https://obsproject.com/forum/resources/clr-host-plugin.21/), but with OBS Studio writing plugins in C# wasn't possible anymore. This has changed as of recently, with the release of .NET 7 and NativeAOT it is possible to produce native code that can be linked with OBS.

### Building
Refer to the [building instructions for my example plugin](https://github.com/YorVeX/ObsCSharpExample#building), they will also apply here.

## Credits
Many thanks to [kostya9](https://github.com/kostya9) for laying the groundwork of C# OBS Studio plugin creation, without him this plugin (and hopefully many more C# plugins following in the future) wouldn't exist. Read about his ventures into this area in his blog posts [here](https://sharovarskyi.com/blog/posts/dotnet-obs-plugin-with-nativeaot/) and [here](https://sharovarskyi.com/blog/posts/clangsharp-dotnet-interop-bindings/). 
