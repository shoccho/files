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
        private uint folders_count = 0;
        private uint files_count = 0;
        private uint64 files_size = 0;
        private GOF.File? goffile = null;
        private GLib.List<unowned GOF.File>? selected_files = null;
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
            margin = 6;
            hexpand = true;
            column_spacing = 6;
            row_spacing = 6;
            row_homogeneous = false;

            spinner = new Gtk.Spinner () {
                valign = Gtk.Align.CENTER,
                halign = valign
            };

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

        public void cancel () {
            if (deep_count_timeout_id > 0) {
                GLib.Source.remove (deep_count_timeout_id);
                deep_count_timeout_id = 0;
            }

            if (update_timeout_id > 0) {
                GLib.Source.remove (update_timeout_id);
                update_timeout_id = 0;
            }

            cancel_cancellable ();
            spinner.active = false;
        }

        private void cancel_cancellable () {
            /* if we're still collecting image info or deep counting, cancel */
            if (cancellable != null) {
                cancellable.cancel ();
                cancellable = null;
            }
        }

       private void real_update (GLib.List<unowned GOF.File>? files) {
            goffile = null;
            title_label.label = "";
            folders_count = 0;
            files_count = 0;
            files_size = 0;

            if (files != null && files.data != null) {
                goffile = files.first ().data;
                scan_list (files);

                update_status ();
            }
        }

        private void update_status () {
            title_label.label = "";
            type_label.label = "";
            folders_count_label.label = "";
            files_count_label.label = "";
            subfolders_count_label.label = "";
            files_size_label.label = "";
            unreadable_count_label.label = "";
            image_resolution_label.label = "";

            /* Determine title and type fields */
            if (files_count + folders_count <= 1) { /* a single file is selected */
                if (goffile.is_network_uri_scheme () || goffile.is_root_network_folder ()) {
                    title_label.label = goffile.get_display_target_uri ();
                } else if (!goffile.is_folder ()) {
                    /* if we have an image, see if we can get its resolution */
                    string? ftype = goffile.get_ftype ();

                    title_label.label = goffile.info.get_name ();
                    type_label.label = goffile.formated_type;

                    if (ftype != null && ftype.substring (0, 6) == "image/") {
                        image_resolution_label.label = _("Loading…");
                        spinner.active = true;
                        cancellable = new Cancellable ();

                        PF.FileUtils.load_image_resolution.begin (goffile,
                                                                  cancellable,
                                                                  (obj, res) => {
                            if (goffile.width <= 0) {
                                image_resolution_label.label = _("Image size could not be determined");
                            } else {
                                image_resolution_label.label = _("%i x %i px").printf (goffile.width, goffile.height);
                            }

                            spinner.active = false;
                            cancellable = null;
                        });
                    }
                } else { // Single folder selected
                    title_label.label = goffile.info.get_name ();
                    type_label.label = goffile.formated_type;
                }
            } else { /* multiple selection */
                title_label.label = _("Selected %u folders, %u files").printf (folders_count, files_count);
            }

            /* Determine count and size fields */
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
        }

        private void schedule_deep_count () {
            cancel ();
            /* Show the spinner immediately to indicate that something will happen when selection stops changing */
            spinner.active = true;

            deep_count_timeout_id = GLib.Timeout.add_full (GLib.Priority.LOW, 1000, () => {
                List<File> folders = null;
                foreach (GOF.File gof in selected_files) {
                    if (gof.is_folder ()) {
                        folders.prepend (gof.location.dup ());
                    }
                }

                /* Marlin.DeepCount now deep counts multiple directories */
                deep_counter = new Marlin.DeepCount (folders);
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

            if (deep_counter != null) {
                if (deep_counter.dirs_count > 0) {
                    /// TRANSLATORS: %u will be substituted by the number of sub folders
                    str = ngettext (_("%u sub-folder"), _("%u sub-folders"), deep_counter.dirs_count);
                    subfolders_count_label.label = str.printf (deep_counter.dirs_count);
                }

                if (deep_counter.files_count >= 0 || deep_counter.file_not_read == 0) {
                    /// TRANSLATORS: %u will be substituted by the number of readable files
                    str = ngettext (_("%u file"), _("%u files"), deep_counter.files_count + files_count);
                    files_count_label.label = str.printf (deep_counter.files_count + files_count);
                }

                if (deep_counter.file_not_read == 0) {
                    files_size_label.label = format_size (deep_counter.total_size + files_size);
                } else {
                    if (deep_counter.total_size > 0) {
                        /// TRANSLATORS: %s will be substituted by the approximate disk space used by the folder
                        files_size_label.label += _("%s approx.").printf (format_size (deep_counter.total_size + files_size));
                    } else {
                        /// TRANSLATORS: 'size' refers to disk space
                        files_size_label.label += _("unknown size");
                    }
                    /// TRANSLATORS: %u will be substituted by the number of unreadable files
                    str = ngettext (_("%u file not readable"), _("%u files not readable"), deep_counter.file_not_read);
                    unreadable_count_label.label = str.printf (deep_counter.file_not_read);
                }
            }
        }

        /* Count the number of folders and number of regular files selected as well as
         * the total size of selected regular files */
        private void scan_list (GLib.List<unowned GOF.File>? files) {
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
                        files_size += PF.FileUtils.file_real_size (gof);
                    }
                } else {
                    warning ("Null file found in OverlayBar scan_list - this should not happen");
                }
            }
        }
    }
}
