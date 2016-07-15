#!/bin/sh

mountDir=/asrDataCenter

# install client software
sudo apt-get install nfs-common

# mkdir dir
[ -r $mountDir ] \
  && echo "dir $mountDir  exists " && exit 2;
sudo mkdir $mountDir

# mount nfs data
sudo mount 192.168.100.35:/asrDataCenter $mountDir

# modify auto mount script to fstab
sudo cp /etc/fstab /etc/fstab.bak
sudo sed -i '$a 192.168.100.35:/asrDataCenter    '$mountDir'   nfs ro,vers=3,rsize=8192,wsize=8192,acdirmin=5,acdirmax=8,hard,proto=tcp 0 0' /etc/fstab
