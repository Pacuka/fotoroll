#include "my_application.h"

#include <dlfcn.h>
#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// ---- System tray (AppIndicator / StatusNotifierItem) ----
// Loaded at run time so neither libayatana-appindicator nor the older
// libappindicator is a build dependency; without either there is no tray.
typedef void* (*IndicatorNew)(const gchar*, const gchar*, int);
typedef void (*IndicatorSetStatus)(void*, int);
typedef void (*IndicatorSetMenu)(void*, GtkMenu*);
typedef void (*IndicatorSetIconThemePath)(void*, const gchar*);
typedef void (*IndicatorSetTitle)(void*, const gchar*);
static IndicatorNew indicator_new = nullptr;
static IndicatorSetStatus indicator_set_status = nullptr;
static IndicatorSetMenu indicator_set_menu = nullptr;
static IndicatorSetIconThemePath indicator_set_icon_theme_path = nullptr;
static IndicatorSetTitle indicator_set_title = nullptr;
static void* indicator = nullptr;

static gboolean load_indicator_library() {
  static gboolean tried = FALSE, ok = FALSE;
  if (tried) return ok;
  tried = TRUE;
  const char* libs[] = {"libayatana-appindicator3.so.1", "libappindicator3.so.1"};
  for (const char* name : libs) {
    void* lib = dlopen(name, RTLD_LAZY | RTLD_LOCAL);
    if (lib == nullptr) continue;
    indicator_new = reinterpret_cast<IndicatorNew>(dlsym(lib, "app_indicator_new"));
    indicator_set_status = reinterpret_cast<IndicatorSetStatus>(dlsym(lib, "app_indicator_set_status"));
    indicator_set_menu = reinterpret_cast<IndicatorSetMenu>(dlsym(lib, "app_indicator_set_menu"));
    indicator_set_icon_theme_path =
        reinterpret_cast<IndicatorSetIconThemePath>(dlsym(lib, "app_indicator_set_icon_theme_path"));
    indicator_set_title = reinterpret_cast<IndicatorSetTitle>(dlsym(lib, "app_indicator_set_title"));
    if (indicator_new && indicator_set_status && indicator_set_menu) {
      ok = TRUE;
      return ok;
    }
  }
  return ok;
}

static GtkWindow* main_window = nullptr;
static gboolean start_hidden = FALSE;   // --hidden (autostart): stay in the tray
static gboolean close_to_tray = FALSE;  // set from the app settings

// "fotoroll/window" channel: full screen, tray, close-to-tray and dropped files.
static FlMethodChannel* window_channel = nullptr;
static gboolean window_is_fullscreen = FALSE;

static void present_window() {
  if (main_window == nullptr) return;
  gtk_widget_show(GTK_WIDGET(main_window));
  gtk_window_present(main_window);
}

static void notify_dart(const gchar* method, FlValue* args) {
  if (window_channel != nullptr) {
    fl_method_channel_invoke_method(window_channel, method, args, nullptr, nullptr, nullptr);
  }
}

static void tray_item_cb(GtkMenuItem* item, gpointer user_data) {
  const gchar* id = static_cast<const gchar*>(user_data);
  if (g_strcmp0(id, "open") == 0) {
    present_window();
  } else if (g_strcmp0(id, "quit") == 0) {
    g_application_quit(g_application_get_default());
  } else {
    g_autoptr(FlValue) value = fl_value_new_string(id);
    notify_dart("onTray", value);
  }
}

// Builds (or rebuilds) the tray menu from [items]: a list of [id, label] pairs,
// where an empty id is a separator.
static gboolean set_tray(FlValue* items) {
  if (!load_indicator_library()) return FALSE;
  if (indicator == nullptr) {
    g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
    g_autofree gchar* dir = exe ? g_path_get_dirname(exe) : g_strdup(".");
    g_autofree gchar* icons = g_build_filename(dir, "data", "flutter_assets", "assets", "branding", nullptr);
    // 0 = APP_INDICATOR_CATEGORY_APPLICATION_STATUS
    indicator = indicator_new(APPLICATION_ID, "fotoroll", 0);
    if (indicator_set_icon_theme_path) indicator_set_icon_theme_path(indicator, icons);
    if (indicator_set_title) indicator_set_title(indicator, "Fotoroll");
  }
  GtkWidget* menu = gtk_menu_new();
  for (size_t i = 0; items != nullptr && i < fl_value_get_length(items); i++) {
    FlValue* pair = fl_value_get_list_value(items, i);
    const gchar* id = fl_value_get_string(fl_value_get_list_value(pair, 0));
    const gchar* label = fl_value_get_string(fl_value_get_list_value(pair, 1));
    GtkWidget* item;
    if (id[0] == '\0') {
      item = gtk_separator_menu_item_new();
    } else {
      item = gtk_menu_item_new_with_label(label);
      g_signal_connect_data(item, "activate", G_CALLBACK(tray_item_cb), g_strdup(id),
                            reinterpret_cast<GClosureNotify>(+[](gpointer data, GClosure*) { g_free(data); }),
                            static_cast<GConnectFlags>(0));
    }
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
  }
  gtk_widget_show_all(menu);
  indicator_set_menu(indicator, GTK_MENU(menu));
  indicator_set_status(indicator, 1);  // APP_INDICATOR_STATUS_ACTIVE
  return TRUE;
}

// Closing the window keeps the app (and the folder backup) running in the tray.
static gboolean window_delete_cb(GtkWidget* widget, GdkEvent* event, gpointer user_data) {
  if (close_to_tray && indicator != nullptr) {
    gtk_widget_hide(widget);
    return TRUE;
  }
  return FALSE;
}

// Files dropped on the window go to Dart as local paths (for uploading).
static void drag_data_received_cb(GtkWidget* widget, GdkDragContext* context, gint x, gint y,
                                  GtkSelectionData* data, guint info, guint time, gpointer user_data) {
  g_auto(GStrv) uris = gtk_selection_data_get_uris(data);
  g_autoptr(FlValue) paths = fl_value_new_list();
  for (gint i = 0; uris != nullptr && uris[i] != nullptr; i++) {
    g_autofree gchar* path = g_filename_from_uri(uris[i], nullptr, nullptr);
    if (path != nullptr) fl_value_append_take(paths, fl_value_new_string(path));
  }
  gtk_drag_finish(context, fl_value_get_length(paths) > 0, FALSE, time);
  if (fl_value_get_length(paths) > 0) notify_dart("onDrop", paths);
}

static gboolean drag_motion_cb(GtkWidget* widget, GdkDragContext* context, gint x, gint y, guint time,
                               gpointer user_data) {
  static gint64 last = 0;
  gint64 now = g_get_monotonic_time();
  if (now - last > 200000) {  // throttle: tell Dart at most 5×/s that a drag hovers
    last = now;
    notify_dart("onDragOver", nullptr);
  }
  return FALSE;  // GTK_DEST_DEFAULT_MOTION does the rest
}

static void drag_leave_cb(GtkWidget* widget, GdkDragContext* context, guint time, gpointer user_data) {
  notify_dart("onDragLeave", nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  // Autostart (--hidden) stays in the tray, if there can be one.
  if (start_hidden && load_indicator_library()) return;
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void window_method_cb(FlMethodChannel* channel, FlMethodCall* call, gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  const gchar* method = fl_method_call_get_name(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "setFullScreen") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    gboolean on = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(args);
    if (on) {
      gtk_window_fullscreen(window);
    } else {
      gtk_window_unfullscreen(window);
    }
    window_is_fullscreen = on;
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "isFullScreen") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(window_is_fullscreen);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "setTray") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(set_tray(fl_method_call_get_args(call)));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "setCloseToTray") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    close_to_tray = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(args);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "show") == 0) {
    present_window();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  // A second launch (single instance) brings the existing window forward.
  if (main_window != nullptr) {
    present_window();
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  main_window = window;
  g_signal_connect(window, "delete-event", G_CALLBACK(window_delete_cb), nullptr);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Fotoroll");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Fotoroll");
  }

  // Window / taskbar icon: the installed theme icon if present, else the bundled PNG.
  gtk_window_set_icon_name(window, APPLICATION_ID);
  {
    g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
    if (exe != nullptr) {
      g_autofree gchar* dir = g_path_get_dirname(exe);
      g_autofree gchar* icon = g_build_filename(
          dir, "data", "flutter_assets", "assets", "branding", "fotoroll.png", nullptr);
      if (g_file_test(icon, G_FILE_TEST_EXISTS)) {
        gtk_window_set_icon_from_file(window, icon, nullptr);
      }
    }
  }

  gtk_window_set_default_size(window, 1280, 800);
  // Start maximized so the layout never extends past a small screen.
  gtk_window_maximize(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Drop files / folders on the window to upload them.
  static const GtkTargetEntry uri_target = {const_cast<gchar*>("text/uri-list"), 0, 0};
  gtk_drag_dest_set(GTK_WIDGET(view), GTK_DEST_DEFAULT_ALL, &uri_target, 1, GDK_ACTION_COPY);
  g_signal_connect(view, "drag-data-received", G_CALLBACK(drag_data_received_cb), nullptr);
  g_signal_connect(view, "drag-motion", G_CALLBACK(drag_motion_cb), nullptr);
  g_signal_connect(view, "drag-leave", G_CALLBACK(drag_leave_cb), nullptr);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "fotoroll/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(window_channel, window_method_cb, window, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  for (gchar** a = self->dart_entrypoint_arguments; *a != nullptr; a++) {
    if (g_strcmp0(*a, "--hidden") == 0) start_hidden = TRUE;
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // Release builds are single-instance: launching again shows the running app
  // (which may be hidden in the tray). Debug builds stay non-unique so tests and
  // `flutter run` can start while the installed app is open.
#ifdef NDEBUG
  const GApplicationFlags flags = G_APPLICATION_DEFAULT_FLAGS;
#else
  const GApplicationFlags flags = G_APPLICATION_NON_UNIQUE;
#endif
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     flags, nullptr));
}
