// Plasma Mobile shell update script (runs once per user, tracked in plasmashellrc).
// Fire HD 8: turn off the home screen's wallpaper blur, which roughly doubles the GPU time
// of the app drawer on the Mali-T720.
var all = desktops();
for (var i = 0; i < all.length; i++) {
    var d = all[i];
    d.currentConfigGroup = ["General"];
    d.writeConfig("wallpaperBlurEffect", 0);
}
