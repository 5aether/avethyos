set positional-arguments

# Show the available shortcuts. Each calls the documented avethyos command.
default:
    @just --justfile /usr/share/avethyos/recipes.just --list

# Download an OS update; reboot later when you choose.
update:
    avethyos update

# Update the OS, apps, command-line tools, and containers.
update-all:
    avethyos update --all

# Check installed tools and your container setup.
doctor:
    avethyos doctor

# Open the app store.
apps:
    avethyos apps store

# Restart the desktop shell.
restart-shell:
    avethyos shell restart

# Test GameMode.
gaming:
    avethyos gaming test

# Read the guide saved in the image.
readme:
    avethyos readme
