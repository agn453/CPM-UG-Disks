# CPM-UG-Disks
CP/M Public Domain 8-inch Disk Images
=====================================

This repository contains disk images of CP/M 8-inch floppy
disks in Dave Dunfield's Image Disk format.

They were written on my Z80 S-100 computer and taken from
boxes of original media masters from various CP/M Users
Group (in the *CPMUG* folder), SIG/M (in the *SIGM* folder)
and from Kelly Smith (in the *KELLY* folder).

I have some more that I'll need to image from the BDS-C
Users Group that I'll add soon.

Each image can be attached to a SIMH AltairZ80 simulator's
floppy disk controller - and, so long as the CP/M system BIOS
software supports Single Density 8-inch disks,
you will be able to read them. I give an example below
using SIMH altairz80 with my distributed version of CP/M Plus - but you
can also use Altair versions of CP/M under the SIMH AltairZ80
simulator too.

Information about Dave Dunfield's ImageDisk format is at

http://www.classiccmp.org/dunfield/img/index.htm


Example using SIMH AltairZ80
----------------------------

* Download the AltairZ80 simulator from
  either Peter Schorn's site at https://schorn.ch/altair.html
  or from Mark Pizzolato's GitHub repository source at
  https://github.com/simh/simh

* Unzip or Build it on your Windows, Linux, macOS or OpenVMS machine
  as per the supplied instructions.

* Copy the altairz80 binary into your search path (I use ~/bin).

* Download my CP/M PLUS distribution (which emulates fairly
  accurately my S-100 system) - from Peter Schorn's site at
  https://schorn.ch/cpm/zip/cpmplus.zip

* Edit the *cpm3bk* text file and attach one of the
  images.

For example using the CP/M UG disk 54 (which contains some
of Dave Ahl's 101 BASIC COMPUTER GAMES)

```
(e.g. using Linux/macOS/Cygwin/Ubuntu on Windows-10)

tweety:~$ mkdir cpmplus; cd cpmplus
tweety:~/cpmplus$ unzip ~/Downloads/cpmplus.zip
..

Edit the file cpm3bk - and add the following after the
'att disk1a2' line -

    att disk1a3 CPMUG054.IMD

then, start the simulator -

tweety:~/cpmplus$ altairz80 cpm3bk

A>L:
..

To exit SIMH use Ctrl-E, the quit to the sim> prompt.

```

* Drive L: corresponds to the attached floppy disk image.

Note:  In user area 3 on drive A: is the program I used to
produce the disk images (D2IMD). It uses a separate copy
of disk I/O routines for raw disk access using the
emulated Godbout/CompuPro DISK1A floppy disk controller.
I've also included the source code in the *d2imd* folder.

