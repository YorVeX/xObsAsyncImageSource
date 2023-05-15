// SPDX-FileCopyrightText: © 2023 YorVeX, https://github.com/YorVeX
// SPDX-License-Identifier: MIT

using System.Runtime.InteropServices;
using System.Text;
using ObsInterop;
namespace xObsAsyncImageSource;

// original image source code this was derived from: https://github.com/obsproject/obs-studio/blob/29.0.2/plugins/image-source/image-source.c

// list of things to test when making bigger changes to this:
//[ ] test automatic reload on file change
//[ ] test animated GIF
//[ ] test changing existing file between GIF and png
//[ ] test loading an invalid file
//[ ] test starting with missing file
//[ ] test with 60 or even more FPS to make threaded conflicts more probable and be sure this is also stable

public class AsyncImageSource
{

  unsafe struct image_source
  {
    public obs_source* source;
    public sbyte* file;
    public bool persistent;
    public bool linear_alpha;
    public long file_timestamp;
    public float update_time_elapsed;
    public ulong last_time;
    public bool active;
    public bool restart_gif;
    public gs_image_file4 if4;

    // extra fields needed for threaded loading
    public long last_load;
    public bool has_new_data;
    public gs_image_file4 new_if4;
    public sbyte* new_file;
    public bool new_persistent;
    public bool new_linear_alpha;
    public long new_file_timestamp;
  }

  #region Helper methods
  public static unsafe void Register()
  {
    var sourceInfo = new obs_source_info();
    fixed (byte* id = Encoding.UTF8.GetBytes(Module.ModuleName))
    {
      sourceInfo.id = (sbyte*)id;
      sourceInfo.type = obs_source_type.OBS_SOURCE_TYPE_INPUT;
      sourceInfo.output_flags = ObsSource.OBS_SOURCE_VIDEO | ObsSource.OBS_SOURCE_SRGB;
      sourceInfo.get_name = &image_source_get_name;
      sourceInfo.create = &image_source_create;
      sourceInfo.destroy = &image_source_destroy;
      sourceInfo.update = &image_source_update;
      sourceInfo.get_defaults = &image_source_defaults;
      sourceInfo.show = &image_source_show;
      sourceInfo.hide = &image_source_hide;
      sourceInfo.get_width = &image_source_getwidth;
      sourceInfo.get_height = &image_source_getheight;
      sourceInfo.video_render = &image_source_render;
      sourceInfo.video_tick = &image_source_tick;
      sourceInfo.missing_files = &image_source_missing_files;
      sourceInfo.get_properties = &image_source_get_properties;
      sourceInfo.icon_type = obs_icon_type.OBS_ICON_TYPE_IMAGE;
      sourceInfo.activate = &image_source_activate;
      sourceInfo.video_get_color_space = &image_source_get_color_space;
      ObsSource.obs_register_source_s(&sourceInfo, (nuint)Marshal.SizeOf(sourceInfo));
    }

  }

  static unsafe long get_modified_timestamp(sbyte* filename)
  {
    try
    {
      return File.GetLastWriteTimeUtc(Marshal.PtrToStringUTF8((IntPtr)filename)!).Ticks;
    }
    catch
    {
      return -1;
    }
  }

  static unsafe void gs_image_file2_free(gs_image_file2* if2)
  {
    ObsImageFile.gs_image_file_free(&if2->image);
  }

  static unsafe void gs_image_file3_free(gs_image_file3* if3)
  {
    gs_image_file2_free(&if3->image2);
  }

  static unsafe void gs_image_file4_free(gs_image_file4* if4)
  {
    gs_image_file3_free(&if4->image3);
  }
  static unsafe void gs_image_file2_init_texture(gs_image_file2* if2)
  {
    ObsImageFile.gs_image_file_init_texture(&if2->image);
  }

  static unsafe void gs_image_file3_init_texture(gs_image_file3* if3)
  {
    gs_image_file2_init_texture(&if3->image2);
  }

  static unsafe void gs_image_file4_init_texture(gs_image_file4* if4)
  {
    gs_image_file3_init_texture(&if4->image3);
  }

  //TODO: test to replace this by the new ObsBmem.bstrdup function: https://github.com/kostya9/NetObsBindings/blob/main/NetObsBindings/ObsInterop/ObsBmem.Manual.cs#LL36
  static unsafe sbyte* bstrdup(sbyte* str)
  {
    var managedStr = Marshal.PtrToStringUTF8((IntPtr)str);
    if (string.IsNullOrEmpty(managedStr))
      return null;
    sbyte* dup = (sbyte*)ObsBmem.bmemdup(str, (nuint)managedStr.Length + 1);
    dup[managedStr.Length] = 0;
    return dup;
  }
  #endregion Helper methods

  #region Source API methods
  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe sbyte* image_source_get_name(void* data)
  {
    Module.Log("image_source_get_name called", ObsLogLevel.Debug);
    fixed (byte* logMessagePtr = "Image (Async)"u8)
      return (sbyte*)logMessagePtr;
  }
  static unsafe void image_source_load(image_source* context)
  {
    // this method differs a lot from the original since this is what is changed to async loading for this plugin

    Module.Log("image_source_load called", ObsLogLevel.Debug);

    context->last_load = DateTime.UtcNow.Ticks;

    if (context->file == null) // mimic the original behavior of this method for this case fully in synchronized context
    {
      Module.Log("image_source_load: null file", ObsLogLevel.Debug);
      Obs.obs_enter_graphics();
      gs_image_file4_free(&context->if4);
      Obs.obs_leave_graphics();
      return;
    }

    context->file_timestamp = get_modified_timestamp(context->file);

    // remember what is supposed to be loaded while still in synchronized context
    var file = bstrdup(context->file);
    var fileString = Marshal.PtrToStringUTF8((IntPtr)file);
    var persistent = context->persistent;
    var linear_alpha = context->linear_alpha;
    var file_timestamp = context->file_timestamp;
    var last_load = context->last_load;
    Task.Run(() =>
    {
      gs_image_file4 if4;
      Module.Log(string.Format("loading texture '{0}'", fileString), ObsLogLevel.Debug);

      var stopwatch = new System.Diagnostics.Stopwatch();
      stopwatch.Start();
      // this is what takes too much time within a frame, the whole reason why this plugin exists is to run this here in a thread:
      ObsImageFile.gs_image_file4_init(&if4, file, linear_alpha ? gs_image_alpha_mode.GS_IMAGE_ALPHA_PREMULTIPLY_SRGB : gs_image_alpha_mode.GS_IMAGE_ALPHA_PREMULTIPLY);
      stopwatch.Stop();

      // entering graphics context also ensures syncing to the main thread for the following operations
      Obs.obs_enter_graphics();
      if (context->last_load > last_load) // if the current load operation is outdated in the meantime discard everything and abort
      {
        Module.Log(string.Format("aborting outdated load of texture '{0}'", fileString), ObsLogLevel.Debug);
        if (file != null)
          ObsBmem.bfree(file);
        gs_image_file4_free(&if4);
        Obs.obs_leave_graphics();
        return;
      }
      if (context->has_new_data) // if there is already new data that hasn't been activated yet discard it now
      {
        Module.Log("discarding outdated previous texture", ObsLogLevel.Debug);
        if (context->new_file != null)
          ObsBmem.bfree(context->new_file);
        gs_image_file4_free(&context->new_if4);
      }
      gs_image_file4_init_texture(&if4);
      context->has_new_data = true;
      context->new_if4 = if4;
      context->new_file = file;
      context->new_persistent = persistent;
      context->new_linear_alpha = linear_alpha;
      if (Convert.ToBoolean(if4.image3.image2.image.loaded))
      {
        // another difference to the original: the timestamp is only updated if the load was successful, see the discussion at https://github.com/obsproject/obs-studio/issues/3011 for details
        context->new_file_timestamp = file_timestamp;
        Module.Log(string.Format("loaded texture '{0}' ({1} ms)", fileString, stopwatch.ElapsedMilliseconds), ObsLogLevel.Debug);
      }
      else
        Module.Log(string.Format("failed to load texture '{0}'", fileString), ObsLogLevel.Warning);
      Obs.obs_leave_graphics();
    });
  }

  static unsafe void image_source_unload(image_source* context)
  {
    Module.Log("image_source_unload called", ObsLogLevel.Debug);
    Obs.obs_enter_graphics();
    context->last_load = DateTime.UtcNow.Ticks;
    gs_image_file4_free(&context->if4);
    Obs.obs_leave_graphics();
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe void image_source_update(void* data, obs_data* settings)
  {
    Module.Log("image_source_update called", ObsLogLevel.Debug);
    var context = (image_source*)data;
    fixed (byte*
      propertyFileIdentifier = "file"u8,
      propertyUnloadIdentifier = "unload"u8,
      propertyLinearAlphaIdentifier = "linear_alpha"u8
    )
    {
      var file = ObsData.obs_data_get_string(settings, (sbyte*)propertyFileIdentifier);
      bool unload = Convert.ToBoolean(ObsData.obs_data_get_bool(settings, (sbyte*)propertyUnloadIdentifier));
      bool linear_alpha = Convert.ToBoolean(ObsData.obs_data_get_bool(settings, (sbyte*)propertyLinearAlphaIdentifier));

      if (context->file != null)
        ObsBmem.bfree(context->file);
      context->file = bstrdup(file);
      context->persistent = !unload;
      context->linear_alpha = linear_alpha;

      /* Load the image if the source is persistent or showing */
      if (context->persistent || Convert.ToBoolean(Obs.obs_source_showing(context->source)))
        image_source_load(context);
      else
        image_source_unload(context);
    }
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe void image_source_defaults(obs_data* settings)
  {
    Module.Log("image_source_get_defaults called", ObsLogLevel.Debug);
    fixed (byte*
      propertyUnloadIdentifier = "unload"u8,
      propertyLinearAlphaIdentifier = "linear_alpha"u8
    )
    {
      ObsData.obs_data_set_default_bool(settings, (sbyte*)propertyUnloadIdentifier, Convert.ToByte(false));
      ObsData.obs_data_set_default_bool(settings, (sbyte*)propertyLinearAlphaIdentifier, Convert.ToByte(false));
    }
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe void image_source_show(void* data)
  {
    Module.Log("image_source_show called", ObsLogLevel.Debug);
    var context = (image_source*)data;

    if (!context->persistent)
      image_source_load(context);
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe void image_source_hide(void* data)
  {
    Module.Log("image_source_hide called", ObsLogLevel.Debug);

    var context = (image_source*)data;

    if (!context->persistent)
      image_source_unload(context);
  }

  static unsafe void restart_gif(void* data)
  {
    // Module.Log("restart_gif called", ObsLogLevel.Debug);
    var context = (image_source*)data;

    if (Convert.ToBoolean(context->if4.image3.image2.image.is_animated_gif))
    {
      context->if4.image3.image2.image.cur_frame = 0;
      context->if4.image3.image2.image.cur_loop = 0;
      context->if4.image3.image2.image.cur_time = 0;

      Obs.obs_enter_graphics();
      ObsImageFile.gs_image_file4_update_texture(&context->if4);
      Obs.obs_leave_graphics();

      context->restart_gif = false;
    }
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe void image_source_activate(void* data)
  {
    Module.Log("image_source_activate called", ObsLogLevel.Debug);
    var context = (image_source*)data;
    context->restart_gif = true;
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe void* image_source_create(obs_data* settings, obs_source* source)
  {
    Module.Log("image_source_create called", ObsLogLevel.Debug);


    var context = ObsBmem.bzalloc<image_source>();
    context->source = source;

    // a C# specific thing, image_source_update() can't be called directly since it was attributed with UnmanagedCallersOnly, a delegate is needed
    delegate* unmanaged[Cdecl]<void*, obs_data*, void> image_source_update_func = &image_source_update;
    image_source_update_func(context, settings);

    return (void*)context;
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe void image_source_destroy(void* data)
  {
    Module.Log("image_source_destroy called", ObsLogLevel.Debug);
    var context = (image_source*)data;

    image_source_unload(context);

    if (context->file != null)
      ObsBmem.bfree(context->file);
    ObsBmem.bfree(context);
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe uint image_source_getwidth(void* data)
  {
    // Module.Log("image_source_getwidth called", ObsLogLevel.Debug);
    return ((image_source*)data)->if4.image3.image2.image.cx;
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe uint image_source_getheight(void* data)
  {
    // Module.Log("image_source_getheight called", ObsLogLevel.Debug);
    return ((image_source*)data)->if4.image3.image2.image.cy;
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe void image_source_render(void* data, gs_effect* effect)
  {
    // Module.Log("image_source_render called", ObsLogLevel.Debug);
    var context = (image_source*)data;
    if (context->if4.image3.image2.image.texture == null)
      return;

    var previous = ObsGraphics.gs_framebuffer_srgb_enabled();
    ObsGraphics.gs_enable_framebuffer_srgb(Convert.ToByte(true));

    ObsGraphics.gs_blend_state_push();
    ObsGraphics.gs_blend_function(gs_blend_type.GS_BLEND_ONE, gs_blend_type.GS_BLEND_INVSRCALPHA);

    fixed (byte* imageParam = "image"u8)
      ObsGraphics.gs_effect_set_texture_srgb(ObsGraphics.gs_effect_get_param_by_name(effect, (sbyte*)imageParam), context->if4.image3.image2.image.texture);

    ObsGraphics.gs_draw_sprite(context->if4.image3.image2.image.texture, 0, context->if4.image3.image2.image.cx, context->if4.image3.image2.image.cy);

    ObsGraphics.gs_blend_state_pop();

    ObsGraphics.gs_enable_framebuffer_srgb(previous);
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe void image_source_tick(void* data, float seconds)
  {
    // Module.Log("image_source_tick called", ObsLogLevel.Debug);
    var context = (image_source*)data;
    var frame_time = Obs.obs_get_video_frame_time();

    context->update_time_elapsed += seconds;

    Obs.obs_enter_graphics();
    if (context->has_new_data) // check if new data is available, needs to be done in graphics context so it is thread-synchronized
    {
      var fileString = Marshal.PtrToStringUTF8((IntPtr)context->new_file);
      Module.Log(string.Format("activating texture '{0}'", fileString), ObsLogLevel.Debug);
      // clean up current data
      if (context->file != null)
        ObsBmem.bfree(context->file);
      gs_image_file4_free(&context->if4);

      // move the new data into place
      context->if4 = context->new_if4;
      context->file = context->new_file;
      context->persistent = context->new_persistent;
      context->linear_alpha = context->new_linear_alpha;
      context->file_timestamp = context->new_file_timestamp;

      Module.Log(string.Format("activated texture '{0}'", fileString), ObsLogLevel.Debug);

      // reset for the next loading procedure
      context->has_new_data = false;
    }
    Obs.obs_leave_graphics();

    if (Convert.ToBoolean(Obs.obs_source_showing(context->source)))
    {
      if (context->update_time_elapsed >= 1.0f)
      {
        var t = get_modified_timestamp(context->file);
        context->update_time_elapsed = 0.0f;

        if (context->file_timestamp != t)
          image_source_load(context);
      }
    }

    if (Convert.ToBoolean(Obs.obs_source_showing(context->source)))
    {
      if (!context->active)
      {
        if (Convert.ToBoolean(context->if4.image3.image2.image.is_animated_gif))
          context->last_time = frame_time;
        context->active = true;
      }

      if (context->restart_gif)
        restart_gif(context);

    }
    else
    {
      if (context->active)
      {
        restart_gif(context);
        context->active = false;
      }

      return;
    }

    if ((context->last_time > 0) && Convert.ToBoolean(context->if4.image3.image2.image.is_animated_gif))
    {
      var elapsed = frame_time - context->last_time;
      var updated = Convert.ToBoolean(ObsImageFile.gs_image_file4_tick(&context->if4, elapsed));

      if (updated)
      {
        Obs.obs_enter_graphics();
        ObsImageFile.gs_image_file4_update_texture(&context->if4);
        Obs.obs_leave_graphics();
      }
    }

    context->last_time = frame_time;
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe obs_properties* image_source_get_properties(void* data)
  {
    Module.Log("image_source_get_properties called", ObsLogLevel.Debug);
    var s = (image_source*)data;

    var properties = ObsProperties.obs_properties_create();

    string defaultPath = Marshal.PtrToStringUTF8((IntPtr)s->file)!;
    if (!string.IsNullOrEmpty(defaultPath))
      defaultPath = Path.GetDirectoryName(defaultPath)!;
    else
      defaultPath = "";

    fixed (byte*
      path = Encoding.UTF8.GetBytes(defaultPath),
      propertyImageIdentifier = Module.ObsText("Image"),
      propertyAsyncInfoIdentifierId = "async_info"u8,
      propertyAsyncInfoIdentifierText = "(Async)"u8,
      propertyFileIdentifier = "file"u8,
      propertyFileCaption = Module.ObsText("File"),
      propertyUnloadIdentifier = "unload"u8,
      propertyUnloadCaption = Module.ObsText("UnloadWhenNotShowing"),
      propertyLinearAlphaIdentifier = "linear_alpha"u8,
      propertyLinearAlphaCaption = Module.ObsText("LinearAlpha"),
#if WINDOWS
      browseFileFilter = @"
      All formats (*.bmp *.tga *.png *.jpeg *.jpg *.jxr *.gif *.psd *.webp);;
      BMP Files (*.bmp);;
      Targa Files (*.tga);;
      PNG Files (*.png);;
      JPEG Files (*.jpeg *.jpg);;
      JXR Files (*.jxr);;
      GIF Files (*.gif);;
      PSD Files (*.psd);;
      WebP Files (*.webp);;
      All Files (*.*)
      "u8
#else
      browseFileFilter = @"
      All formats (*.bmp *.tga *.png *.jpeg *.jpg *.gif *.psd *.webp);;
      BMP Files (*.bmp);;
      Targa Files (*.tga);;
      PNG Files (*.png);;
      JPEG Files (*.jpeg *.jpg);;
      GIF Files (*.gif);;
      PSD Files (*.psd);;
      WebP Files (*.webp);;
      All Files (*.*)
      "u8
#endif
    )
    {
      var prop = ObsProperties.obs_properties_add_text(properties, (sbyte*)propertyAsyncInfoIdentifierId, (sbyte*)propertyAsyncInfoIdentifierText, obs_text_type.OBS_TEXT_INFO);
      
      prop = ObsProperties.obs_properties_add_path(properties, (sbyte*)propertyFileIdentifier, (sbyte*)propertyFileCaption, obs_path_type.OBS_PATH_FILE, (sbyte*)browseFileFilter, (sbyte*)path);

      prop = ObsProperties.obs_properties_add_bool(properties, (sbyte*)propertyUnloadIdentifier, (sbyte*)propertyUnloadCaption);

      prop = ObsProperties.obs_properties_add_bool(properties, (sbyte*)propertyLinearAlphaIdentifier, (sbyte*)propertyLinearAlphaCaption);
    }
    return properties;
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe void missing_file_callback(void* src, sbyte* new_path, void* data)
  {
    Module.Log("missing_file_callback called", ObsLogLevel.Debug);
    var s = (image_source*)src;

    var settings = Obs.obs_source_get_settings(s->source);
    fixed (byte* propertyFileIdentifier = "file"u8)
      ObsData.obs_data_set_string(settings, (sbyte*)propertyFileIdentifier, new_path);
    Obs.obs_source_update(s->source, settings);
    ObsData.obs_data_release(settings);
  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe obs_missing_files* image_source_missing_files(void* data)
  {
    Module.Log("image_source_missing_files called", ObsLogLevel.Debug);
    var s = (image_source*)data;
    var files = ObsMissingFiles.obs_missing_files_create();

    var file = Marshal.PtrToStringUTF8((IntPtr)s->file);
    if (!string.IsNullOrEmpty(file))
    {
      if (!File.Exists(file))
      {
        var missingFile = ObsMissingFiles.obs_missing_file_create(s->file, &missing_file_callback, (int)obs_missing_file_src.OBS_MISSING_FILE_SOURCE, s->source, null);
        ObsMissingFiles.obs_missing_files_add_file(files, missingFile);
      }
    }
    return files;

  }

  [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
  static unsafe gs_color_space image_source_get_color_space(void* data, nuint count, gs_color_space* preferred_spaces)
  {
    // Module.Log("image_source_get_color_space called", ObsLogLevel.Debug);
    var s = (image_source*)data;
    return (s->if4.image3.image2.image.texture != null) ? s->if4.space : gs_color_space.GS_CS_SRGB;
  }

  #endregion Source API methods


}