/***
    Copyright (c) 2020 elementary LLC <https://elementary.io>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

***/

namespace Marlin.View {
    public class PropertiesSidebar : Gtk.Grid {
        const int IMAGE_LOADER_BUFFER_SIZE = 8192;
        const int STATUS_UPDATE_DELAY = 200;
        Cancellable? cancellable = null;
        bool image_size_loaded = false;
        private uint folders_count = 0;
        private uint files_count = 0;
//~         private uint64 folders_size = 0;
        private uint64 files_size = 0;
        private GOF.File? goffile = null;
        private GLib.List<unowned GOF.File>? selected_files = null;
        private uint8 [] buffer;
        private GLib.FileInputStream? stream;
        private Gdk.PixbufLoader loader;
        private uint update_timeout_id = 0;
        private Marlin.DeepCount? deep_counter = null;
        private uint deep_count_timeout_id = 0;
        private Gtk.Label title_label;
        private Gtk.Label type_label;
        private Gtk.Label folders_count_label;
        private Gtk.Label subfolders_count_label;
        private Gtk.Label files_count_label;
        private Gtk.Label files_size_label;
        private Gtk.Label unreadable_count_label;
        private Gtk.Label image_resolution_label;
        private Gtk.Spinner spinner;

        construct {
            hexpand = true;
            column_spacing = 6;
            row_spacing = 6;
            row_homogeneous = false;

            spinner = new Gtk.Spinner () {
                valign = Gtk.Align.CENTER,
                halign = valign
            };

            buffer = new uint8[IMAGE_LOADER_BUFFER_SIZE];
            title_label = new Gtk.Label ("Title") {
                halign = Gtk.Align.START
            };
            type_label = new Gtk.Label ("Type") {
                halign = Gtk.Align.START
            };
            folders_count_label = new Gtk.Label ("Folder Count") {
                halign = Gtk.Align.START
            };
            subfolders_count_label = new Gtk.Label ("SubFolder Count") {
                halign = Gtk.Align.START
            };
            files_count_label = new Gtk.Label ("Files count") {
                halign = Gtk.Align.START
            };
            files_size_label = new Gtk.Label ("Files Size") {
                halign = Gtk.Align.START
            };
            unreadable_count_label = new Gtk.Label ("Unreadable") {
                halign = Gtk.Align.START
            };
            image_resolution_label = new Gtk.Label ("Image Resolution") {
                halign = Gtk.Align.START
            };

            attach (title_label, 0, 0, 2, 1);
            attach (type_label, 0, 1, 2, 1);
            attach (folders_count_label, 0, 2, 1, 1);
            attach (subfolders_count_label, 0, 3, 1, 1);
            attach (files_count_label, 0, 4, 1, 1);
            attach (files_size_label, 0, 5, 1, 1);
            attach (unreadable_count_label, 0, 6, 1, 1);
            attach (image_resolution_label, 0, 7, 1, 1);
            attach (spinner, 0, 8, 1, 1);
            show_all ();
        }

        ~PropertiesSidebar () {
            cancel ();
        }

        public void selection_changed (GLib.List<unowned GOF.File> files) {
            cancel ();
            var n_files = files.length ();
            if (n_files == 0) {
                visible = false;
            } else {
                visible = true;
            }

            update_timeout_id = GLib.Timeout.add_full (GLib.Priority.LOW, STATUS_UPDATE_DELAY, () => {
                if (files != null) {
                    selected_files = files.copy ();
                } else {
                    selected_files = null;
                }

                real_update (selected_files);
                update_timeout_id = 0;
                return GLib.Source.REMOVE;
            });
        }

        public void reset_selection () {
            selected_files = null;
        }


        /** Function to be called when view is going to be destroyed or going to show another folder
 *        * and on a selection change.
*         **/
        public void cancel () {
            deep_count_cancel ();

            if (update_timeout_id > 0) {
                GLib.Source.remove (update_timeout_id);
                update_timeout_id = 0;
            }

            cancel_cancellable ();
            spinner.active = false;
        }

        private void deep_count_cancel () {
            /* Do not cancel updating of selected files when hovered file changes */
            if (deep_count_timeout_id > 0) {
                GLib.Source.remove (deep_count_timeout_id);
                deep_count_timeout_id = 0;
            }
        }

        private void cancel_cancellable () {
            /* if we're still collecting image info or deep counting, cancel */
            if (cancellable != null) {
                cancellable.cancel ();
                cancellable = null;
            }
        }

       private void real_update (GLib.List<unowned GOF.File>? files) {
warning ("real_update");
            goffile = null;
            title_label.label = "";
            folders_count = 0;
            files_count = 0;
//~             folders_size = 0;
            files_size = 0;

            if (files != null && files.data != null) {
                goffile = files.first ().data;
                scan_list (files);

                update_status ();
            }
        }

        private void update_status () {
warning ("update status");
            title_label.label = "";
            type_label.label = "";
            folders_count_label.label = "";
            files_count_label.label = "";
            subfolders_count_label.label = "";
            files_size_label.label = "";
            unreadable_count_label.label = "";
            image_resolution_label.label = "";

warning ("files count %u, folders_count %u", files_count, folders_count);
            if (files_count + folders_count <= 1) { /* a single file is selected */
                if (goffile.is_network_uri_scheme () || goffile.is_root_network_folder ()) {
                    title_label.label = goffile.get_display_target_uri ();
                } else if (!goffile.is_folder ()) {
                    /* if we have an image, see if we can get its resolution */
                    string? ftype = goffile.get_ftype ();

//~                     if (goffile.format_size == "" ) { /* No need to keep recalculating it */
//~                         goffile.format_size = format_size (PropertiesWindow.file_real_size (goffile));
//~                     }

                    title_label.label = goffile.info.get_name ();
                    type_label.label = goffile.formated_type;
//~                     files_count_label.label = _("%u file").printf (1);
//~                     files_size_label.label = goffile.format_size;

//~                     str = "%s- %s (%s)".printf (goffile.info.get_name (),
//~                                                 goffile.formated_type,
//~                                                 goffile.format_size);

                    if (ftype != null && ftype.substring (0, 6) == "image/" &&     /* file is image and */
                        (goffile.width > 0 ||                                    /* resolution already determined  or */
                        !((ftype in Marlin.SKIP_IMAGES) || goffile.width < 0))) { /* resolution can be determined. */

                        load_resolution.begin (goffile);
                    }
                } else {
//~                     str = "%s - %s".printf (goffile.info.get_name (), goffile.formated_type);
                    title_label.label = goffile.info.get_name ();
                    type_label.label = goffile.formated_type;
//~                     folders_count_label.label = _("%u folder").printf (1);
warning ("schedule deep count");
//~                     schedule_deep_count ();
                }
            } else { /* multiple selection */
//~                 var fsize = format_size (files_size);
                title_label.label = _("Multiple selection");
//~                 size.label = format_size (files_size);
//~                 if (folders_count > 1) {
//~                     str = _("%u folders").printf (folders_count);
//~                     folders_count_label.label = _("%u folders").printf (folders_count);
//~                     if (files_count > 0) {
//~                         str += ngettext (_(" and %u other item (%s) selected").printf (files_count, fsize),
//~                                          _(" and %u other items (%s) selected").printf (files_count, fsize),
//~                                          files_count);
//~                         files_count_label.label = ngettext (_("%u file").printf (files_count),
//~                                                             _("%u files").printf (files_count),
//~                                                             files_count);
//~                     }

//~                     if (files_count > 0) {
//~                         files_size_label.label = format_size (files_size);
//~                     } else {
//~                         files_size_label.label = "";
//~                     }
//~                 } else if (folders_count == 1) {
//~                     str = _("%u folder").printf (folders_count);
//~                     folders_count_label.label = _("%u folder").printf (folders_count);
//~                     schedule_deep_count ();
//~                         str += ngettext (_(" and %u other item (%s) selected").printf (files_count, fsize),
//~                                          _(" and %u other items (%s) selected").printf (files_count, fsize),
//~                                          files_count);
//~                     files_count_label.label = ngettext (_("%u file").printf (files_count),
//~                                                         _("%u files").printf (files_count),
//~                                                         files_count);

//~                     files_size_label.label = format_size (files_size);
//~                 } else { /* folder_count = 0 and files_count > 1 */
//~                     str = _("%u items selected (%s)").printf (files_count, fsize);
//~                     files_count_label.label = _("%u files").printf (files_count);
//~                     files_size_label.label = format_size (files_size);
//~                 }
            }

            if (folders_count > 0) {
                folders_count_label.label = ngettext (_("%u folder").printf (folders_count),
                                                    _("%u folders").printf (folders_count),
                                                    folders_count);
                schedule_deep_count ();
            } else {
                files_count_label.label = ngettext (_("%u file").printf (files_count),
                                                    _("%u files").printf (files_count),
                                                    files_count);

                files_size_label.label = format_size (files_size);
            }
//~             return str;
        }

        /* Deep counts are only done when a single folder is selected */
        private void schedule_deep_count () {
            cancel ();
            /* Show the spinner immediately to indicate that something will happen when selection stops changing */
            spinner.active = true;
            deep_count_cancel ();

            deep_count_timeout_id = GLib.Timeout.add_full (GLib.Priority.LOW, 1000, () => {
                List<File> files = null;
                foreach (GOF.File gof in selected_files) {
                    if (gof.is_folder ()) {
                        files.prepend (gof.location.dup ());
                    }
                }

//~                 deep_counter = new Marlin.DeepCount (goffile.location);
                deep_counter = new Marlin.DeepCount (files);
                deep_counter.finished.connect (update_status_after_deep_count);

                cancel_cancellable ();
                cancellable = new Cancellable ();
                cancellable.cancelled.connect (() => {
                    if (deep_counter != null) {
                        deep_counter.finished.disconnect (update_status_after_deep_count);
                        deep_counter.cancel ();
                        deep_counter = null;
                        cancellable = null;
                    }
                    spinner.active = false;
                });

                deep_count_timeout_id = 0;
                return GLib.Source.REMOVE;
            });
        }

        private void update_status_after_deep_count () {
            string str;
            cancellable = null;
            spinner.active = false;

//~             title_label.label = "%s - %s (".printf (goffile.info.get_name (), goffile.formated_type);
//~             title_label.label = goffile.info.get_name ();

            if (deep_counter != null) {
                if (deep_counter.dirs_count > 0) {
                    /// TRANSLATORS: %u will be substituted by the number of sub folders
                    str = ngettext (_("%u sub-folder"), _("%u sub-folders"), deep_counter.dirs_count);
warning ("str %s", str);
                    subfolders_count_label.label = str.printf (deep_counter.dirs_count);
                }

                if (deep_counter.files_count >= 0 || deep_counter.file_not_read == 0) {
                    /// TRANSLATORS: %u will be substituted by the number of readable files
                    str = ngettext (_("%u file"), _("%u files"), deep_counter.files_count + files_count);
                    files_count_label.label = str.printf (deep_counter.files_count + files_count);
                }

                if (deep_counter.file_not_read == 0) {
                    files_size_label.label = format_size (deep_counter.total_size + files_size);
//~                     size.label += ")";
                } else {
                    if (deep_counter.total_size > 0) {
                        /// TRANSLATORS: %s will be substituted by the approximate disk space used by the folder
                        files_size_label.label += _("%s approx.").printf (format_size (deep_counter.total_size + files_size));
                    } else {
                        /// TRANSLATORS: 'size' refers to disk space
                        files_size_label.label += _("unknown size");
                    }

//~                     title_label.label += ") ";
                    /// TRANSLATORS: %u will be substituted by the number of unreadable files
                    str = ngettext (_("%u file not readable"), _("%u files not readable"), deep_counter.file_not_read);
                    unreadable_count_label.label = str.printf (deep_counter.file_not_read);
                }
            }
        }

        /* Count the number of folders and number of files selected as well as the total size of selected files */
        private void scan_list (GLib.List<unowned GOF.File>? files) {
warning ("SCAN LIST");
            if (files == null) {
                return;
            }

            foreach (unowned GOF.File gof in files) {
                if (gof != null && gof is GOF.File) {
                    if (gof.is_folder ()) {
                        folders_count++;
                        goffile = gof;
                    } else {
                        files_count++;
                        files_size += PropertiesWindow.file_real_size (gof);
                    }
                } else {
                    warning ("Null file found in OverlayBar scan_list - this should not happen");
                }
            }
        }

        /* code is mostly ported from nautilus' src/nautilus-image-properties.c */
        private async void load_resolution (GOF.File goffile) {
            if (goffile.width > 0) { /* resolution may already have been determined */
                on_size_prepared (goffile.width, goffile.height);
                return;
            }

            var file = goffile.location;
            image_size_loaded = false;

            try {
                stream = yield file.read_async (0, cancellable);
                if (stream == null) {
                    error ("Could not read image file's size data");
                }

                loader = new Gdk.PixbufLoader.with_mime_type (goffile.get_ftype ());
                loader.size_prepared.connect (on_size_prepared);

                cancel_cancellable ();
                cancellable = new Cancellable ();

                yield read_image_stream (loader, stream, cancellable);
            } catch (Error e) {
                warning ("Error loading image resolution in OverlayBar: %s", e.message);
            }
            /* Gdk wants us to always close the loader, so we are nice to it */
            try {
                stream.close ();
            } catch (GLib.Error e) {
                debug ("Error closing stream in load resolution: %s", e.message);
            }
            try {
                loader.close ();
            } catch (GLib.Error e) { /* Errors expected because may not load whole image */
                debug ("Error closing loader in load resolution: %s", e.message);
            }
            cancellable = null;
        }

        private void on_size_prepared (int width, int height) {
            if (goffile == null) { /* This can occur during rapid rubberband selection */
                return;
            }
            image_size_loaded = true;
            goffile.width = width;
            goffile.height = height;
            title_label.label = "%s (%s — %i × %i)".printf (goffile.formated_type, goffile.format_size, width, height);
        }

        private async void read_image_stream (Gdk.PixbufLoader loader, FileInputStream stream,
                                              Cancellable cancellable) {
            ssize_t read = 1;
            uint count = 0;
            while (!image_size_loaded && read > 0 && !cancellable.is_cancelled ()) {
                try {
                    read = yield stream.read_async (buffer, 0, cancellable);
                    count++;
                    if (count > 100) {
                        goffile.width = -1; /* Flag that resolution is not determinable so do not try again*/
                        goffile.height = -1;
                        /* Note that Gdk.PixbufLoader seems to leak memory with some file types. Any file type that
                         * causes this error should be added to Marlin.SKIP_IMAGES array */
                        critical ("Could not determine resolution of file type %s", goffile.get_ftype ());
                        break;
                    }

                    loader.write (buffer);

                } catch (IOError e) {
                    if (!(e is IOError.CANCELLED)) {
                        warning (e.message);
                    }
                } catch (Gdk.PixbufError e) {
                    /* errors while loading are expected, we only need to know the size */
                } catch (FileError e) {
                    warning (e.message);
                } catch (Error e) {
                    warning (e.message);
                }
            }
        }
    }
}
