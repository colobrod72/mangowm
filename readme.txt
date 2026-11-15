
      <----Display_Manager_Service ---->
        ===================
   systemctl status display-manager.service
 sudo systemctl disable --now UNIT.service    UNIT(менеджер входа?)
    sudo systemctl enable --now greetd
       sudo systemctl disable --now greetd
          sudo reboot

  <---- Install_System_Live: Arch_Linux Noctalia --->
      ===========================

sudo pacman -S --needed base-devel meson just greetd dbus wayland wayland-protocols wlroots0.20 libinput libglvnd freetype2 fontconfig cairo pango harfbuzz libxkbcommon glib2 tomlplusplus noctalia nlohmann-json stb ibwebp libjxl librsvg libxml2

 <--Install_System_Live: Debian_Linux Noctalia -->
          ==========================

   wget https://pkg.noctalia.dev/deb/nickh-archive-keyring.deb && sudo dpkg -i nickh-archive-keyring.deb
   
   sudo wget -O /etc/apt/sources.list.d/noctalia-unstable.sources https://pkg.noctalia.dev/deb/noctalia-unstable.sources
   
sudo apt update
sudo apt install noctalia noctalia-greeter umbriel xdg-desktop-portal-umbriel

sudo systemctl restart greetd

sudo apt install meson g++ just greetd dbus libwayland-dev wayland-protocols libwlroots-0.20-dev libinput-dev libegl-dev libgles-dev libfreetype-dev libfontconfig-dev libcairo2-dev libpango1.0-dev libharfbuzz-dev libxkbcommon-dev libglib2.0-dev libtomlplusplus-dev nlohmann-json3-dev libstb-dev libwebp-dev libjxl-dev librsvg2-dev libxml2-dev grim slurp swappy wl-clipboard cliphist wlr-randr swayidle wlopm qml6-module-qtquick-effects xdg-desktop-portal-wlr xdg-desktop-portal-gtk x11-xserver-utils gawk curl wget pavucontrol pulsemixer pipewire-audio thunar thunar-archive-plugin thunar-volman gvfs-backends gvfs-fuse dialog mtools cifs-utils unzip nwg-look xsettingsd lxpolkit quickshell rofi dunst libnotify-bin btop pamixer playerctl brightnessctl wlsunset power-profiles-daemon pulseaudio-utils xdg-utils pkexec python3 mangowc xwayland awww build-essential

      <---- mango_config ----->
 config.conf: "source=~/.local/share/mango/defaults.conf
                    source=~/.config/mango/autostart.conf
                    source=~/.config/mango/keybinds.conf
                    source=~/.config/mango/rules.conf
                    source-optional=~/.config/mango/local.conf "

          <---- .config/mango/ ----->
 autostart.conf,config.conf,keybinds.conf,local.conf,rules.conf,wallpaper

          <-----.local/share/mango/ ------>
 defaults.conf
 

       <-------- Butter_Sway_Install --------->
         git clone https://justaguy.dev/butter/sway.git
                    cd sway
              ./install.sh


       <-------- Butter_Mango_Install --------->
       git clone https://justaguy.dev/butter/mango.git
                    cd sway
              ./install.sh


        <------ Autologin_Arch_Linux Greetd ------>

    sudo systemctl enable --now greetd
sudo systemctl disable --now greetd

sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo nano /etc/systemd/system/getty@tty1.service.d/autologin.conf

[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --noreset --noclear --autologin username - ${TERM}















