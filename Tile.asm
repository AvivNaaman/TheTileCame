IDEAL
MODEL small
STACK 100h
DATASEG
; image start filename
start_filename db 'start.bmp',0
; image stuff
filehandle dw ?
Header db 54 dup (0)
Palette db 256*4 dup (0)
ScrLine db 320 dup (0)
retAddress dw 0
; clock
clock equ es:6CH
; x, y & color
x dw 0
y dw 0
color db 3
y_done dw 0 ; temp for storing done y writing
; score
score db 0
; random generation - seed
seed dw 0
; repeats
repeats dw 20
; timer counters
nextSecond dw 0
second20 dw 0 ; the 20th second
; messages
ImageErrorMessage db 'An Error Occured During image file reading', 13, 10 ,'$'
GameOverMessage db 13,10,'   Game Over! You Scored: $'
PressAnyKeyToContinueMessage db 13,10,13,10,13,10,'      Press Any Key to continue$'

CODESEG
; --------------------------
proc OpenFile
    ; Open file
    push bp
    mov bp, sp
    mov dx, [bp+4]
    mov ah, 3Dh
    xor al, al
    int 21h
    jc OpenFile_error
    mov [filehandle], ax
    jmp OpenFile_end
    OpenFile_error:
    mov dx, offset ImageErrorMessage
    mov ah, 9h
    int 21h
    OpenFile_end:
    pop bp
    ret 2
endp OpenFile
proc ReadHeader
    ; Read BMP file header, 54 bytes
    mov ah,3fh
    mov bx, [filehandle]
    mov cx,54
    mov dx,offset Header
    int 21h
    ret
endp ReadHeader
proc ReadPalette
    ; Read BMP file color palette, 256 colors * 4 bytes (400h)
    mov ah,3fh
    mov cx,400h
    mov dx,offset Palette
    int 21h
    ret
endp ReadPalette
proc CopyPal
    ; Copy the colors palette to the video memory
    ; The number of the first color should be sent to port 3C8h
    ; The palette is sent to port 3C9h
    mov si,offset Palette
    mov cx,256
    mov dx,3C8h
    mov al,0
    ; Copy starting color to port 3C8h
    out dx,al
    ; Copy palette itself to port 3C9h
    inc dx
    PalLoop:
        ; Note: Colors in a BMP file are saved as BGR values rather than RGB .
        mov al,[si+2] ; Get red value .
        shr al,2 ; Max. is 255, but video palette maximal
        ; value is 63. Therefore dividing by 4.
        out dx,al ; Send it .
        mov al,[si+1] ; Get green value .
        shr al,2
        out dx,al ; Send it .
        mov al,[si] ; Get blue value .
        shr al,2
        out dx,al ; Send it .
        add si,4 ; Point to next color .
        ; (There is a null chr. after every color.)
    loop PalLoop
    ret
endp CopyPal
proc CopyBitmap
    ; BMP graphics are saved upside-down .
    ; Read the graphic line by line (200 lines in VGA format),
    ; displaying the lines from bottom to top.
    mov ax, 0A000h
    mov es, ax
    mov cx,200
    PrintBMPLoop :
    push cx
    ; di = cx*320, point to the correct screen line
    mov di,cx
    shl cx,6
    shl di,8
    add di,cx
    ; Read one line
    mov ah,3fh
    mov cx,320
    mov dx,offset ScrLine
    int 21h
    ; Copy one line into video memory
    cld ; Clear direction flag, for movsb
    mov cx,320
    mov si,offset ScrLine
    rep movsb ; Copy line to the screen
    pop cx
    loop PrintBMPLoop
    ret
endp CopyBitmap
; Waits until the mouse is clicked on the button, between (140, 125) to (182,145)
proc WaitForBtnClick
	WaitForBtnClick_loop:
		mov ax, 03h
		int 33h
		cmp bx, 01h
		jne WaitForBtnClick_loop
		shr cx, 1 ; X, dx Y
		; 140 <= x <= 182
		cmp cx, 182
		jg WaitForBtnClick_loop
		cmp cx, 140
		jl WaitForBtnClick_loop
		; 125 <= Y <= 145
		cmp dx, 125
		jl WaitForBtnClick_loop
		cmp dx, 145
		jg WaitForBtnClick_loop
	
	WaitForBtnClick_loop_end:
		ret
endp
; Generates random values for x, y, and color
proc GenerateRandom
	push es
	mov ax, 40h
	mov es, ax
	; generate values for x,y,color vars.
	; Unfortanatly, the code from assembly gvahim didn't work well
	; so I used the LCG algorithm: (seed*const0+const1)%(MaxResult+1)
	; seed is the new generated number each time, so numbers are "pure" random, as much as can be right now.
	cmp [seed], 0
	jne ContinueGenerate
	mov ax, [clock]
	mov [seed], ax
	ContinueGenerate:
		mov ax, [seed]
		mov bx, 487
		mul bx ; ax:dx = seed*487
		mov bx, 357
		add ax, bx ; dx:ax = seed*487+357
		mov bx, 280 ; don't get out of the screen
		add ax, dx
		xor dx, dx ; reset dx, to prevent crashes
		div bx ; dx = (seed*487+357)%280 -> 0<=dx<=279
		mov [x], dx
		mov [seed], dx
		
		
		mov ax, [seed]
		mov bx, 487
		mul bx ; ax:dx = seed*487
		mov bx, 357
		add ax, bx ; dx:ax = seed*487+357
		mov bx, 160 ; don't get out of the screen
		add ax, dx
		xor dx, dx ; reset dx, to prevent crashes
		div bx ; dx = (seed*487+357)%160 -> 0<=dx<=159
		mov [y], dx
		mov [seed], dx
		
		mov ax, [seed]
		mov bx, 487
		mul bx ; ax:dx = seed*487
		mov bx, 357
		add ax, bx ; dx:ax = seed*487+357
		mov bx, 63
		add ax, dx
		xor dx, dx ; reset dx, to prevent crashes
		div bx ; dx = (seed*487+357)%63 -> 0<=dx<=62
		mov [color], dl
		inc [color] ; we don't like the color 0 (black)
		mov [seed], dx
		pop es
	ret
endp GenerateRandom
; Initializes mouse - we might need that more than once
proc InitMouse
	; Initialize mouse
	mov ax, 0h
	int 33h
	mov ax, 1h
	int 33h
	ret
endp InitMouse
; Draws a square at (x,y) coordinates
proc DrawSquare
	; no passing here yet. we're currently using global varriable.
	mov cx, 40
		DrawSquare_Row:
			mov [y_done], cx
			push cx
			mov cx, 40
			DrawSquare_Col:
				push cx
				add cx, [x]
				mov dx, [y]
				add dx, [y_done]
				mov ax, 0
				mov al, [color]
				mov ah, 0ch
				int 10h
				pop cx
				loop DrawSquare_Col
			pop cx
			loop DrawSquare_Row
	mov [y_done], 0
	ret
endp
; clears the screen
proc ClearScreen
	; clear screen
	mov ax,0A000h
	mov es,ax
	xor ax, ax ; set ax to 0 - black
	mov cx,32000
	cld ; clear dir flag
	rep stosw ; copy ax value (0) to ax:cx, and repeat until cx is 0
	ret
endp
; plays success click sound
proc MakeSuccessSound
	; activate spekare
	in al, 61h
	or al, 00000011b
	out 61h, al
	; get access
	mov al, 0B6h
	out 43h, al
	; send sound in freq of 2135Hz => send 022Fh to port 42h, by sections:
	mov al, 02Fh
	out 42h, al
	mov al, 02h
	out 42h, al
	; run for 12 ticks:
	mov ax, [clock]
	mov cx, 12
	MakeSuccessSound_WaitByCxTicks:
		cmp ax, [clock]
		je MakeSuccessSound_WaitByCxTicks
		loop MakeSuccessSound_WaitByCxTicks
	; disable speaker
	in al, 61h
	and al, 11111100b
	out 61h, al
	ret
endp
; plays failed click sound
proc MakeFailedSound
	; activate spekare
	in al, 61h
	or al, 00000011b
	out 61h, al
	; get access
	mov al, 0B6h
	out 43h, al
	; send sound in freq of 2135Hz => send 0710h to port 42h, by sections:
	mov al, 010h
	out 42h, al
	mov al, 07h
	out 42h, al
	; run for 15 ticks:
	mov ax, [clock]
	mov cx, 15
	MakeFailedSound_WaitByCxTicks:
		cmp ax, [clock]
		je MakeFailedSound_WaitByCxTicks
		loop MakeFailedSound_WaitByCxTicks
	; disable speaker
	in al, 61h
	and al, 11111100b
	out 61h, al
	ret
endp
; initializes the clock for usage
proc InitClock
	mov ax, 40h
	mov es, ax
	ret
endp
; prints the score 
proc PrintScore
	; clear screen at 100% and make the mouse gone
	mov ax, 13h
	int 10h
	mov dx, offset GameOverMessage 
	mov ah, 9h
	int 21h ; print game over
	; print score
	xor dx, dx
	xor ax, ax
	mov al, [score]
	mov bx, 10
	div bx
	add dx, 48 ; *10^0
	add ax, 48 ; *10^1
	PrintScoreAndTimeLeft_PrintPower1:
		push dx		
		cmp ax, 48
		jbe PrintScoreAndTimeLeft_PrintPower0 ; if 0, don't print it
		; print *10^1 first
		mov dx, ax
		mov ah, 02h
		int 21h
	PrintScoreAndTimeLeft_PrintPower0:
		pop dx
		mov ah, 02h
		int 21h
	mov dx, offset PressAnyKeyToContinueMessage 
	mov ah, 9h
	int 21h ; print press any key to continue
	ret
endp
start:
    mov ax, @data
    mov ds, ax
    ; Graphic mode
    mov ax, 13h
    int 10h
    ; Show start screen
    push offset start_filename ; pass filename by ref
    call OpenFile
    call ReadHeader
    call ReadPalette
    call CopyPal
    call CopyBitmap
	; Initialize mouse
	call InitMouse
	; Wait until button is clicked
	call WaitForBtnClick
	; reset graphics
	mov ax, 13h
	int 10h
	call InitMouse ; initialize mouse again
	call InitClock
	mov ax, [clock]
	add ax, 400 ; ax=now+20sec
	mov [second20], ax
	mov cx, [repeats]
	MainLoop:
		call ClearScreen ; Clear the screen
		call InitClock
		mov ax, [clock]
		cmp ax, [second20]
		jae MainLoop_End ; if 20 secs past, stop the program
		; when will a second past (by ticks)
		mov ax, [clock]
		add ax, 18 ; 18*0.055=0.99
		mov [nextSecond], ax
		
		call GenerateRandom ; generate the random values for x, y and color
		call DrawSquare ; draws square at (x,y) and by the color
		WaitSecond:
			call InitClock
			mov ax, [clock]
			cmp ax, [nextSecond]
			jge MainLoop_Next ; 1 sec past, redraw
			; second not past yet, check mouse:
			mov ax, 03h
			int 33h
			cmp bx, 01h
			jne WaitSecond ; not clicked, wait for click again
			shr cx, 1 ; adjust mouse X for 320 instead of 640 (VGA stuff)
			; read mouse color:
			mov bh, 0h
			mov ah, 0dh
			int 10h
			cmp al, [color] ; check if color's the same
			jne MainLoop_FailedClick ; if not, wait for another click
			MainLoop_SuccessClick:
				; Everything Nice now. Make sound & increase score:
				inc [score]
				call MakeSuccessSound ; make the nice sound of success
				jmp MainLoop_Next
			MainLoop_FailedClick:
				; User failed in clicking 
				call MakeFailedSound
		MainLoop_Next:
			dec [repeats] ; get iterations count
			cmp [repeats], 0
			jg MainLoop
	MainLoop_End:
	call PrintScore
	; wait for key press to continue
	WaitForKeypress:
		mov ah, 0bh
		int 21h      ;RETURNS AL=0 : NO KEY PRESSED, AL!=0 : KEY PRESSED.
		cmp al, 0
		je  WaitForKeypress	
	
    ; Back to text mode
    mov ah, 0
    mov al, 2
    int 10h

exit:
mov ax, 4c00h
int 21h
END start



