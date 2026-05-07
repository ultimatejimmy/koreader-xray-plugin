#!/bin/bash
set -e

echo "Updating package list..."
sudo apt-get update

echo "Installing LuaJIT and Luarocks..."
sudo apt-get install -y luajit luarocks build-essential liblua5.1-0-dev

echo "Installing Busted testing framework..."
sudo luarocks install busted

echo "Dependencies installed successfully!"
busted --version
