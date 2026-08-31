-- Omarchy Pets: screensaver mode.
-- The pet's screensaver layer is a translucent dim over the desktop; blur it so
-- the wallpaper shows through softly instead of a flat black screen.
hl.layer_rule({ match = { namespace = "omarchy-pets-screensaver" }, blur = true, ignore_alpha = 0.1, no_anim = true, animation = "none" })
-- No animation on the pet layer either (it is always mapped).
hl.layer_rule({ match = { namespace = "omarchy-pets" }, no_anim = true, animation = "none" })
-- Omarchy's screensaver runs in a fullscreen black terminal underneath the pet
-- layer. Make that window invisible so the blurred desktop is what you see;
-- it still receives the keyboard input that ends the screensaver.
o.window({ class = "^org.omarchy.screensaver$" }, { opacity = 0.0 })
