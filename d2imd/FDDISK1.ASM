	title 'FDDISK1 CompuPro DISK 1 Double density diskette module'

;		+-----------------------+
;		|			|
;		|     F D D I S K 1	|
;		|			|
;		+-----------------------+
;
;           CP/M-80 Version 3  --  Modular BIOS
;
;	    Disk I/O Module for Godbout Disk-1
;	         based diskette systems
;
;   Modification History:
;
;	07-May-1985	Tony Nicholson	Initial version
;	16-Sep-1985	Tony Nicholson	Pretty up retry message
;	12-Oct-1985	Tony Nicholson	Add support for 5-1/4" drives
;	21-Jan-1987	Tony Nicholson	Use the common memory ?phexm
;					routine (added to BIOSKRNL)
;					for showing status bytes in
;					error messages
;	11-Jun-2008	Tony Nicholson	Add SIMH and LDRBIOS conditionals to
;					get this running on the simulator
;	30-Jul-2008	Tony Nicholson	Support reading of Ferguson
;					Bigboard-II 1024 byte 9 sector
;					per track double density format
;					and use USERF BIOS entry for
;					toggling skewing of 1024 byte 8
;					sector per track disks (this
;					should allow recovery of files
;					from BigBoard-II 8" disks)
;	01-Aug-2008	Tony Nicholson	Also, added capability to
;					support IBM-PC/AT HD 5.25"
;					1.2Mbyte floppy media using
;					code that was implemented in the
;					FDBB2 driver module.
;					
;					
;

	maclib	z80
	maclib	cpm3
	maclib	ioports
	maclib	config		; configuration constants

;
; *** Disk drive dispatching tables for linked BIOS
;
	public	fddd0		; all versions support disk unit 0

  if s100$system and not ldrbios
	public	fddd1
    if disk1$minicd
	public	fddd2,fddd3	; 5.25" TEAC HD drives
    endif
  endif

  if simh and not ldrbios
	public	fddd1,fddd2,fddd3
  endif

  if disk1$userf
	public	userf,d1flag
  endif

  if disk1$ibm$at and not disk1$minicd
	error	'?FDDISK1 **ERROR** IBM-AT support requires MINICD true'
  endif

;
; *** Variables containing parameters passed by BDOS
;
	extrn	@adrv,@rdrv
	extrn	@dma,@trk,@sect
	extrn	@dbnk,@dtyp,@cbnk

;
; *** System Control Block variables
;
	extrn	@ermde		; BDOS error mode

;
; *** Utility routines in standard BIOS
;
	extrn	?wboot		; warm boot vector
	extrn	?pmsg		; print message @<HL> up to 00, saves <BC> & <DE>
	extrn	?pderr		; print BIOS disk error header
	extrn	?conin,?cono	; con in and out
	extrn	?const		; get console status

;
; *** Useful external routine (added to BIOSKRNL)
;
	extrn	?phexm		; print @<HL> in hex plus a space to console
	extrn	?getch		; con in uppercase with echo 
;
; *** Error message components
;
	public	rd$msg,wr$msg,er$msg,op$name

;
; *** Stack for memory block moves for Cromemco Bank Select Memory
;
  if bankmem
	extrn	?bnksl		; memory bank select
	extrn	copy$stack
  endif

cr	equ	13
lf	equ	10
bell	equ	7

;
;	Maximum disk sector size
;
hstsiz	equ	1024
ntraks	equ	77	;Number of tracks per surface
drm	equ	256	;Maximum number of directory entries

  if disk1$bb2$read9
dsm	equ	674	;Maximum number of 2K blocks per drive
  else
dsm	equ	600	;Maximum number of 2K blocks per drive
  endif

;
;	CP/M disk control block equates
;	which define the disk types
;
unknown$dtyp equ 0FEh	;Value for unknown disk type (forces SELDSK)
dsks1	equ	0	;Single density 128, single sided.
dsks2	equ	1	;Single density 128, double sided.
dskd1	equ	2	;Double density 256, single sided.
dskd2	equ	3	;Double density 256, double sided.
dskd3	equ	4	;Double density 512, single sided
dskd4	equ	5	;Double density 512, double sided
dskd5	equ	6	;Double density 1024, single sided
dskd6	equ	7	;Double density 1024, double sided
  if disk1$bb2$read9
dskd7	equ	8	;Double density 1024, single sided, 9 sector
dskd8	equ	9	;Double density 1024, double sided, 9 sector
h9bb2	equ	12h	;Sector-ID "H" bits for 9 sector format
n9bb2	equ	4	;Pseudo-N value for 9 sector format
  endif
;
;	Disk drive constants
;
stepr	equ	3		;Remex & YE-DATA 3ms step
srt	equ	16-stepr	;Controller value
hut	equ	240/16		;Head unload = 240 ms
hdlt	equ	35		;Head load = 35 ms
nd	equ	0b		;Set DMA mode
mrtry	equ	10		;Number of re-tries

;
; *** Extended Disk Parameter Headers (XPDHs)
;
	dseg		; Banked memory

	dw	fd$write
	dw	fd$read
	dw	fd$login
	dw	fd$init0
	db	0		; relative drive zero
	db	unknown$dtyp	; disk type
  if ldrbios
	; The LDRBIOS doesn't get GENCPM to allocate buffer space
	; so we need to define it here and in dirbcb and dtabcb tables
fddd0	dw	xltd3		; sector translation table
	db	0,0,0,0,0,0,0,0,0 ; 72 bit scratch area
	db	0		; media flag
	dw	maxdpb		; address of DPH
	dw	csv		; address of disk change check area
	dw	alv		; address of disk allocation bitmap
	dw	dirbcb		; address of directory BCB
	dw	dtabcb		; address of data BCB
	dw	0FFFFh		; hashing table disabled
	db	0
  else
fddd0	dph	xltd3,maxdpb
  endif

  if not ldrbios
	dw	fd$write
	dw	fd$read
	dw	fd$login
	dw	fd$init1
	db	1		; relative drive one
	db	unknown$dtyp	; disk type
fddd1	dph	xltd3,maxdpb

    if simh or disk1$minicd
	dw	fd$write
	dw	fd$read
	dw	fd$login
	dw	fd$init2
	db	2		; relative drive one
	db	unknown$dtyp	; disk type
fddd2	dph	xltd3,maxdpb

	dw	fd$write
	dw	fd$read
	dw	fd$login
	dw	fd$init3
	db	3		; relative drive one
	db	unknown$dtyp	; disk type
fddd3	dph	xltd3,maxdpb
    endif
  endif

;
; DPB - Disk Parameter Header blocks for each particular disk density
;

	cseg		; DPB must be resident

dpbs1:		;Single density 128, single sided
	dpb	128,26,77,1024,64,2

dpbs2:		;Single density 128, double sided
	dpb	128,26,154,2048,128,2	;** changed from 4 reserved tracks

dpbd1:		;Double density 256, single sided
	dpb	256,26,77,2048,128,2

dpbd2:		;Double density 256, double sided
	dpb	256,26,154,2048,256,4

dpbd3:		;Double density 512, single sided
	dpb	512,15,77,2048,128,2

dpbd4:		;Double density 512, double sided

  if disk1$ibm$at	; 80-Track drive ** FDBB2 had only 2 reserved tracks
	dpb	512,15,160,2048,128,2
  else
	dpb	512,15,154,2048,256,4
  endif

dpbd5:		;Double density 1024, single sided
	dpb	1024,8,77,2048,128,2

dpbd6:		;Double density 1024, double sided
	dpb	1024,8,154,2048,256,4

  if disk1$bb2$read9
dpbd7:		;Double density 1024, single sided, 9 sector
	dpb	1024,9,77,2048,128,2

dpbd8:		;Double density 1024, double sided, 9 sector
	dpb	1024,9,154,2048,128,2

maxdpb	equ	dpbd8		;Largest capacity dpb
  else

maxdpb	equ	dpbd6		;Largest capacity dpb
 
  endif
;
;	Physical Sector Translation Tables
;
xlts:	skew	26,6,0		;Single density 128 byte
xltd1:	skew	26,9,0		;Double density 256 byte
xltd2:	skew	15,4,0		;Double density 512 byte
xltd3:	skew	8,3,0		;Double density 1024 byte

	dseg		; Banked memory

xtable:	dw	xlts		;Single 128
	dw	xltd1		;Double 256
	dw	xltd2		;Double 512
	dw	xltd3		;Double 1024
  if disk1$bb2$read9
	dw	0		;BigBoard-II 9 sector has no skew
  endif

;
; *** Disk I/O routines for standardized BIOS interface
;
; Initialization entry point.
;
;	called for first time initialization.
;
fd$init0:
fd$init1:
fd$init2:
fd$init3:	; none required for the DISK 1
	ret

;
; *** LOGIN Drive
;
;
; This entry is called when a logical drive is about to
; be logged into for the purpose of density determination.
;
; It adjusts the parameters contained in the disk
; parameter header pointed at by <DE>
;
fd$login:
	push	d		; save XDPH pointer
	lda	@rdrv		; and fetch relative
	mov	c,a		; drive number to determine
	call	tread		; the disk type
	pop	d
	rnz			; return if couldn't determine type
	dcx	d		; Save disk type in
	stax	d		; XDPH
	inx	d
	mov	l,a		; use disk type to form
	mvi	h,0		; the DPB address
	mov	b,h
	mov	c,l
	dad	h		; (17 bytes per DPB)
	dad	h
	dad	h
	dad	h
	dad	b
	lxi	b,dpbs1
	dad	b
	xchg			; Now DE=DPB address
	push	h		; and HL=DPH address
	lxi	b,12		; Compute DPH DPB address
	dad	b		; (12 byte offset)
	mov	m,e		; and store DPB address
	inx	h		; into DPH
	mov	m,d

  if disk1$userf and disk1$skew
	cpi	dskd5		; Single-sided 1024 byte/sector?
	jrnz	nmlsk1		; No, continue with normal skew
	push	psw		; Yes, save disk type
	lda	d1flag		; If skew disabled
	bit	d1f$skew,a	;  then print a status message
	jrnz	nmlsk2
	lxi	d,noskew$msg
	call	showtype
	pop	psw
	lxi	d,0		; Store zero in DPH sector
nmlsk3:	pop	h		; translation field
	mov	m,e
	inx	h
	mov	m,d
	ret

nmlsk2:	pop	psw		; Restore disk type
	lxi	d,xltd3		;  and go store regular skew
	jr	nmlsk3		;  table address in DPH

nmlsk1:
  endif

  if disk1$ibm$at
	cpi	dskd4		; If IBM-PC/AT format
	jrnz	notibm		;  print a message
	lxi	h,ibm$at$msg
	call	showtype
notibm:
  endif

  if disk1$bb2$read9 and disk1$debug
	cpi	dskd7		; If BB2 1024-9 format
	jrc	notbb2		;  print a message
	lxi	h,bb2$msg
	call	showtype
notbb2:
  endif
	ani	11111110b	; Remove sided bit from type
	mov	e,a		; and form address of the
	mvi	d,0		; sector translation table
	lxi	h,xtable
	dad	d
	xchg
	pop	h		; HL = DPH address again
	ldax	d		; so fetch and store the
	mov	m,a		; translation table address
	inx	h		; in the DPH
	inx	d
	ldax	d
	mov	m,a
	ret

;
; *** Disk READ and WRITE entry points.
;
; These entries are called with the following arguments:
;
; relative drive number in @rdrv (8 bits)
; absolute drive number in @adrv (8 bits)
; disk transfer address in @dma (16 bits)
; disk transfer bank	in @dbnk (8 bits)
; disk track address	in @trk (16 bits)
; disk sector address	in @sect (16 bits)
; disk type		in @dtyp (8 bits)
; pointer to XDPH in <DE>
;
; They transfer the appropriate data, perform retries
; if necessary, then return an error code in <A>
;

fd$read:
	lhld	@trk		;Get track number to read
	mov	a,h
	ora	L
	mvi	a,dsks1		;Track 0 is always single
	jrz	readtk0		; density
	lda	@dtyp		;Get selected disk type
readtk0:
	sta	acttyp
	cpi	dskd1
	mvi	a,f$rdat	;Read Single density
	jrc	read$sector
	mvi	a,f$rdat+f$dble	;Read Double density
read$sector:
	lxi	h,rd$msg	; point at " Read " msg

  if not bankmem
	jr	rw$common
  else
	; Cromemco Bank Select Memory cards only do 16bit address
	; so we have to do disk transfers to common memory buffer
	; and block move it to the CP/M DMA address
	call	rw$common
	push	psw		;Save status
	call	bufsize		;Compute buffer size
	lxi	h,disk1$buf
	lded	@dma		;Copy to CP/M DMA address
	call	copy$dma
	pop	psw		;Restore status
	ret
  endif

fd$write:
	lhld	@trk		;Get track number to write
	mov	a,h
	ora	L
	mvi	a,dsks1		;Track 0 is always single
	jrz	writetk0	; density
	lda	@dtyp
writetk0:
	sta	acttyp

  if disk1$bb2$read9
	cpi	dskd7		;If a BigBoard-II 9 sector format
	jrnc	nowrite		; then make it write-protected
  endif

	cpi	dskd1
	mvi	a,f$wrt		;Write to single density floppy
	jrc	write$sector	;If non-blocked transfer
	mvi	a,f$wrt+f$dble
write$sector:

  if bankmem
	; Cromemco Bank Select memory
	push	psw		;Save command byte
	call	bufsize		; and copy write buffer
	lxi	d,disk1$buf	; to common memory
	lhld	@dma
	call	copy$dma
	pop	psw		;Restore command
  endif
	lxi	h,wr$msg	; point at " Write "

;
;
;	R W $ C O M M O N   --  Preform final transfer processing.
;
;	ENTRY	A = Disk controller command byte
;		HL = Address of operation type message

rw$common:
	shld	op$name		; save message for errors

	call	prcdch		;Process command, drive, cylinder
	lxi	h,ciopb		;Set buffer address
	mov	m,c		;Set command
	inx	h
	mov	m,b		;Set drive
	inx	h
	mov	m,e		;Set cylinder
	inx	h
	mov	m,d		;Set head
	mov	e,a		;Save N field
  if disk1$bb2$read9
	cpi	n9bb2		;BigBoard-II 9 sector N value?
	jrnz	rwc0
	mov	a,m		;Yes, set offset bits in the
	ori	h9bb2		; sector-ID "H" field
	mov	m,a
  endif
rwc0:	inx	h
	lda	@sect		;Get sector
	mov	c,a
	inr	a
	mov	m,a		;Set beginning sector
	inx	h
	mov	a,e		;Get type
	mov	m,a		;Set N field
  if disk1$bb2$read9
	cpi	n9bb2		;If Bigboard-II 9 sector type (N=4)
	jrnz	rwc1
	dcr	m		;make it a 1024 byte sector (N=3)
rwc1:
  endif
	inx	h
	add	a		;N*2
	push	h
	lxi	h,cmdtyp
	mov	e,a
	mvi	d,0
	dad	d
	xchg
	pop	h
	lda	numsec		;Compute ending sector number
	add	c
	mov	m,a		;Set EOT
	inx	h
	ldax	d
	mov	m,a		;Set GPL field
	inx	d
	inx	h
	ldax	d
	mov	m,a		;Set DTL

more$retries:
	mvi	a,mrtry		;Set retry count
fnl1:	sta	rtry		;Clear retry count
	lda	ciopb+2		;Get cylinder number
	call	doseek		;Seek to proper track
	jrnz	fnl3		;If seek error

  if bankmem
	lxi	h,disk1$ade	;Cromemco Bank Select Memory Common buffer
  else
	lxi	H,@dbnk		;Real CP/M DMA address
  endif

	mvi	b,3
fnl2:	mov	a,m		;get ext adr
	out	dma
	dcx	h		;data is backward in memory
	djnz	fnl2		;If not all 3 bytes

	lxi	h,ciopb
	mvi	b,ciopl		;Set command buffer length
	mvi	c,7
	call	exec		;perform operation
	cpi	40h
	jrnz	fnl3		;If error
	lda	disk$status+1
	sui	80h
	rz			;If no errors
	ani	00000010b	;Check write protected
	jrz	fnl3		;No

  if disk1$bb2$read9
nowrite: xra	a
  endif

	ori	02h		;Yes, return write protected
	ret

fnl3:	lda	rtry		;Get retry counter
	dcr	a
	jrnz	fnl1		;If not permanent error

	lda	@dtyp		;Check for media change
	push	psw
	lda	@rdrv
	mov	c,a
	call	tread		;Determine disk type
	mov	c,a		; and save it in C
	jrnz	fnl4		;Non-recoverable if not determined
	pop	psw		;Is it the same type?
	cmp	c
	jrz	fnl5		;Yes, must be non-recoverable
	ori	0ffh		;Media has changed
	ret

fnl4:	pop	psw

fnl5:	lda	@ermde		; suppress error message
	cpi	0ffh		; if BDOS is returning
	jrz	hard$error	; errors to application

;
; Had permanent error, print message like:
;
; BIOS Err on d: Tnn Smm <operation> Status s0 s1 s2, Retry (Y/N)?
;
	call	?pderr		; print message header
	lhld	op$name
	call	?pmsg		; last operation tried
  if disk1$debug
	lxi	h,cmd$msg	; print " Cmd "
	call	?pmsg
	lxi	h,ciopb		; Dump command bytes
	mvi	b,9
dump$cmd:
	call	?phexm
	inx	h
	djnz	dump$cmd
  endif
	lxi	h,status$msg	; print " Status "
	call	?pmsg
	lxi	h,disk$status	; Dump status bytes in hex
  if disk1$debug
	mvi	b,7		;  (all 7 result codes)
  else
	mvi	b,3		;  (ST0, ST1 and ST2 only)
  endif
dump$status:
	call	?phexm
	inx	h
	djnz	dump$status
	lxi	h,er$msg
	call	?pmsg		; print " Retry (Y/N)? "
	call	?getch		; get operator response
	lxi	h,yes$msg	; was it a "Y"?
	cmp	m
	jrnz	no$retry	; No
	call	?pmsg		; Yes, then retry 10 more times
	lxi	h,crlf$msg
	call	?pmsg
	jmp	more$retries
no$retry:
	lxi	h,no$msg	; Print "No" message
	call	?pmsg
	lxi	h,crlf$msg
	call	?pmsg
hard$error:			; otherwise, return a
	xra	a		; Non-recoverable media
	ori	1		; error to the BDOS
	ret

rtry:	db	0

;
;	Command buffer disk type dependent values.
;

cmdtyp:	;	GPL  DTL
	db	007h,128	;Single density
	db	00Eh,255	;Double density 256 bytes
	db	01Bh,255	;Double density 512 bytes
	db	035h,255	;Double density 1024 bytes
  if disk1$bb2$read9
	db	00Ah,255	;Double density 1024 bytes 9 sector
  endif
;
;	TREAD - Determine floppy disk type.
;
;	ENTRY	C = Selected drive.
;
;	Exit	Zbit set = no error
;		A = disk type (0-7) [standard version]
;		A = disk type (0-9) [BigBoard-II 9 sector enabled]
;

tread:	mov	a,c
  if disk1$minicd
	sta	tdrive		;Save drive for 5.25" minifloppy test
  endif
	call	specify		;Set disk parameters
	lxi	h,dsts
	mvi	b,dstsl
	call	execp		;Perform command
	mvi	b,1
	call	gcmps		;Get the one status byte
	ani	020h		;Mask ready bit
	jrnz	trd1		;If drive is ready
	ori	0ffh		;Clear zero flag for error
	ret

trd1:
  if disk1$minicd
	lda	tdrive		;Is it a 5-1/4" drive?
	cpi	2		; on relative drive 2 or 3
  endif
	lda	disk$status	;Get status byte
  if disk1$minicd
	jrc	trd11		;No
	ori	00001000b	;Yes, force 2 sided
trd11:
  endif
	ani	00001000b	;Mask TS bit
	rrc
	rrc
	rrc
	sta	sidefl		;Save sided flag
	lxi	h,recal		;Do a test seek
	mvi	b,lrecal
	call	moveto		;Process command
	rnz			;If error
	mvi	a,2		;Seek to track two
	call	doseek		;Do seek
	rnz			;If error
	mvi	a,f$drid+f$dble	;Try MFM first
	sta	drid

trd2:	lxi	h,drid
	mvi	b,dridl
	mvi	c,7
	call	execx		;Process command
	jrz	trd3		;If read valid
	lda	drid
	xri	f$dble		;Compliment MFM bit
	sta	drid
	ani	f$dble
	jrz	trd2		;If FM not tried
	ori	0ffh
	ret

trd3:	lda	disk$status+6	;Get N field
	add	a		;*2
	mov	b,a

  if disk1$bb2$read9
	cpi	dskd5		;Is it 1024 bytes per sector?
	jrc	trd4		;No
	lda	disk$status+4	;Get H field from sector ID
	ani	h9bb2		;Are BigBoard-II 9-Sector bits set?
	jrz	trd4		;No
	mvi	b,dskd7		;Yes, change disk type
  endif

trd4:	lda	sidefl
	ora	b		;Combine N with sided flag
	cmp	a		;Set zero flag
	ret

if disk1$minicd
tdrive	equ	sidefl		;Re-use sidefl for temporary
endif

sidefl:	db	0

dsts:	db	f$dsts,0
dstsl	equ	$-dsts

recal:	db	f$reca,0
lrecal	equ	$-recal

drid:	db	f$drid,0
dridl	equ	$-drid

;
;	PRCDCH -- Process Command, Drive, Cylinder, and Head.
;
;	ENTRY	A = command.
;
;	EXIT	A = N field (0..4).
;		B = drive.
;		C = command.
;		D = head.
;		E = cylinder.
;

prcdch:	mov	c,a		;Save Command
	lda	@rdrv
	mov	b,a
	lhld	@trk		;Get track number
	lda	acttyp		;Get type
	xchg
	mov	h,a		;Save type
  if disk1$bb2$read9
	cpi	dskd8		;BigBoard-II DSDD-1024 9?
	jrnz	nmlch
	mov	a,e		;Yes, then it has a different
	cpi	ntraks		; scheme for head and cylinder
	jrc	cdch1		; (side changes after last track
	sui	ntraks		;  on side 0 to side 1)
	add	a		;Cylinder = 2*(track - ntraks)
	mov	e,a		; (this is divided by 2 below)
	inr	d		;Make it head 1
	mov	a,d
	jr	chdrv1		; and go and combine it with the drive
  endif
nmlch:	ani	1
	jrz	cdch1		;If single sided
	mov	a,e
	ani	1
	mov	d,a		;Set head
chdrv1:	rlc
	rlc
	ora	b		;Combine head with drive
	mov	b,a
	mov	a,e		;Adjust track for cylinder
	rar
	mov	e,a

cdch1:	mov	a,h
	ani	0feh		;Remove sided bit
	rrc
	ret

;
;	Seek to specified Track/Sector
;
;	Entry	A = Track (actually the Cylinder)
;

doseek:
	sta	dsekc+2		;Save cylinder into controller
	lxi	h,dsekc		; command block
	mvi	b,dsekl
;	jr	moveto
;
;	Move head according to command.
;
;	ENTRY	HL = address of command buffer.
;		B = length of command buffer.
;
;	Exit	Z bit set if no error.
;

moveto:
	call	execp		;Perform seek
mvto1:	in	ints
	ora	a
	jp	mvto1		;if not complete
	mvi	a,f$rsts
	out	fdcd		;request status
	mvi	b,2
	call	gcmps		;Get status
	cpi	20h
	rz			;If seek complete
	lda	disk$status	;Get true status byte
	ani	3h		;Mask disk unit
	mov	c,a
	lda	@rdrv
	cmp	c
	jrnz	mvto1		;If not proper unit
	ori	0ffh		;Clear zero flag
	ret

;
;	SPECIFY - Specify disk drive characteristics.
;

specify:
	lxi	h,spec+1
	mvi	b,lspec
	mvi	c,0
	lda	stepms
	ori	hut
	mov	m,A
	dcx	h
	jr	exec		;Specify disk command

stepms:	db	(srt shl 4)+0	;Step rate

dsekc:	db	f$seek,0,0
dsekl	equ	$-dsekc

spec:	db	f$spec
	db	(srt shl 4)+hut
	db	(hdlt shl 1)+nd
lspec	equ	$-spec

;
;	E X E C U T E   D I S K   F U N C T I O N
;
;	Entry	HL = FWA of command buffer.
;		B  = # of bytes to output
;		C  = # of bytes for status
;
;	Exit	If C <> 0 then see GCMPS.
;

execp:	mvi	c,0		;Set no status byte

execx:	inx	h
	lda	@rdrv		;Set drive into command buffer
	mov	m,a
	dcx	h

exec:
exec1:	in	fdcs
	ora	a
	jp	exec1		;if no master ready bit
	mov	a,m		;command byte
	out	fdcd		;to controller
	inx	h
	djnz	exec1		;if more bytes
	mov	a,c		;# of status bytes+1
	ora	a
	rz			;if no status bytes
	mov	b,c		;# of status bytes

exec2:	in	ints
	ora	a
	jp	exec2		;If operation not complete

;
;	Get completion status.
;
;	Entry	B= # of status bytes to read
;
;	Exit	disk$status = status bytes read in.
;		A = [disk$status] and 0F8h.
;		Flags set according to above value in A.
;

gcmps:
	lxi	h,disk$status	;Set status buffer address
gcmps2:	in	fdcs
	ora	a
	jp	gcmps2		;if not ready
	in	fdcd		;Get status byte
	mov	m,a
	inx	h
	djnz	gcmps2		;wait until all done

	lda	disk$status	;Get first status byte
	ani	0f8h		;Mask out HD, US1 and US0
	ret

  if disk1$userf
;
;	USERF -- Get and Set options
;
; *** User defined function to set/read the FDDISK1
;	control flag byte
;
; Entry: <C>	=00 to Get
;		=FF to Set
;	<B> is flag byte to set
;
; Returns with <A> containing value in control byte
; Destroys <HL>
;
	cseg		; Common memory resident

userf:	lxi	h,d1flag
	mov	a,c
	ora	a
	jrz	userget
	mov	m,b
userget:
	mov	a,m
	ret

;
; *** FDDISK1 control byte
;
; Bits are defined as follows
d1f$verbose equ 7
d1f$skew equ 6

d1flag:	db	1100$0000b	; Default is verbose and skew enabled

  endif

	dseg		; Banked memory
;
; *** Error message components
;
rd$msg:		db	' Read',0
wr$msg:		db	' Write',0
  if disk1$debug
cmd$msg:	db	cr,lf,'Command ',0
status$msg:	db	cr,lf,'Status  ',0
er$msg:		db	cr,lf,'Retry (Y/N)? ',0
  else
status$msg:	db	' Status ',0
er$msg:		db	'Retry (Y/N)? ',0
  endif
yes$msg:	db	'Yes',0
no$msg:		db	'No',0

;
; *** Show disk type
;
; Enter with <HL> pointing to null terminated message string
; Saves <PSW> <BC> and <DE>
;
showtype:
	push	psw
  if disk1$userf
	lda	d1flag		;Don't print if verbose off
	bit	d1f$verbose,a
	jrz	noshow
  endif
	push	h		; save text pointer
	lda	@rdrv		; put ascii unit number
	adi	'0'		;  into message
	sta	show$unit
	lxi	h,show$msg	; print it
	call	?pmsg
	xthl			; print text
	call	?pmsg
	pop	h
	call	?pmsg		; new line
noshow:	pop	psw
	ret

show$msg:	db	cr,lf,'%FDDISK1 unit '
show$unit:	db	'0 is type ',0
crlf$msg:	db	cr,lf,0

  if disk1$userf and disk1$skew
noskew$msg:	db	'1024x8 with no skew',0
  endif

  if disk1$bb2$read9 and disk1$debug
bb2$msg:	db	'BigBoard-II 1024x9 Read-Only',0
  endif

  if disk1$ibm$at
ibm$at$msg:	db	'IBM-AT 80 track 512x15',0
  endif

op$name:	dw	rd$msg

disk$status:
	ds	8		;8272 Result status cells

numsec:	db	1		;Number of sectors to transfer at a time
acttyp:	ds	1		;Active disk type

;
;	DISK 1 Controller command buffer
;
ciopl	equ	9		;Length
ciopb:	ds	ciopl		;Disk command buffer

  if ldrbios

	cseg		; LDRBIOS BCBs must be resident
;
;	Buffer control blocks and buffers for CPMLDR
;
dirbcb:	db	0ffh		;DRV Drive with record in DIRBUF
	db	0,0,0		;REC# Record position in buffer
	db	0		;WFLG Buffer written flag
	db	0		;00 BDOS scratch byte
	dw	0		;TRACK Physical track location
	dw	0		;SECTOR Physical sector location
	dw	dirbuf		;BUFFAD Address of buffer
	db	0		;BANK Bank containing buffer
	dw	0		;LINK Link to next BCB

dtabcb:	db	0ffh		;DRV Drive with record in DIRBUF
	db	0,0,0		;REC# Record position in buffer
	db	0		;WFLG Buffer written flag
	db	0		;00 BDOS scratch byte
	dw	0		;TRACK Physical track location
	dw	0		;SECTOR Physical sector location
	dw	datbuf		;BUFFAD Address of buffer
	db	0		;BANK Bank containing buffer
	dw	0		;LINK Link to next BCB

dirbuf:	ds	hstsiz

datbuf:	ds	hstsiz

csv:	ds	(drm/4)+1

alv:	ds	(dsm/4)+2
  endif

  if bankmem
	; Cromemco Bank Select Memory buffer shuffling

	dseg		;Banked memory

;
;  Compute selected disk's physical sector size
;
bufsize:
	lda	acttyp
    if disk1$bb2$read9
	cpi	dskd7		;If BigBoard-II 9 sector format
	jrc	buf0
	mvi	a,dskd5		;fudge 1024 byte
buf0:
    endif
	ani	00000110b
	rrc
	lxi	h,128
	ora	a
	jrz	buf1
buf2:	dad	h
	dcr	a
	jrnz	buf2
buf1:	mov	b,h
	mov	c,L
	ret

	cseg		;Common memory

;
;  Copy to/from common memory read/write buffer
;

copy$dma:
	sspd	copy$stack	;Swap to common memory
	lxi	sp,copy$stack	; stack
	lda	@cbnk		;Get current bank
	push	psw		; and save
	lda	@dbnk		;Select DMA bank
	call	?bnksl
	ldir			;Copy data
	pop	psw		;Restore bank
	call	?bnksl
	lspd	copy$stack
	ret

disk1$dma:
	dw	disk1$buf	;Disk read/write buffer
disk1$ade:
	db	0		;Global (common) memory
disk1$buf:
	ds	hstsiz

  endif ; bankmem

	end
