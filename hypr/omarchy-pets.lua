-- Omarchy Pets: screensaver mode.
-- The screensaver layer paints the blurred wallpaper itself (Hyprland's blur is
-- off in Omarchy); it only needs to appear without a layer animation.
hl.layer_rule({ match = { namespace = "omarchy-pets-screensaver" }, no_anim = true, animation = "none" })
-- No animation on the pet layer either (it is always mapped).
hl.layer_rule({ match = { namespace = "omarchy-pets" }, no_anim = true, animation = "none" })
-- Omarchy's screensaver runs in a fullscreen black terminal underneath the pet
-- layer. Make that window invisible so the blurred desktop is what you see;
-- it still receives the keyboard input that ends the screensaver.
o.window({ class = "^org.omarchy.screensaver$" }, { opacity = 0.0 })
