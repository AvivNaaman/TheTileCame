IDEAL
MODEL small
STACK 100h
DATASEG
; --------------------------
; Your variables here
; start image stuff
start_filename db 'start.bmp',0
filehandle dw ?
Header db 54 dup (0)
Palette db 256*4 dup (0)
ScrLine db 320 dup (0)
retAddress dw 0
; clock
clock equ es:6CH
reqClock dw 0
; x, y & color
x dw 0
y dw 0
color db 0
y_done dw 0 ; temp for storing done y writing
; points
points db 0
; repeats
repeats dw 20
; error message
ImageErrorMessage db 'An Error Occured During image file reading', 13, 10 ,'$'
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
    ret 6
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
proc GenerateValues
	mov ax, 40h
	mov es, ax
	mov di, 0
	; Generate X
	mov ax, [clock]
	mov bx, [word cs:di]
	xor ax, bx
	and ax, 0101000000b ; 320 - x value
	mov [x], ax
	inc di
	; Generate Y
	mov ax, [clock]
	xor bx, bx
	mov bx, [word cs:di]
	xor ax, bx
	and ax, 11001000b ; 200 - y value
	mov [y], ax
	inc di
	; Generate color
	mov ax, [clock]
	xor bx,bx
	mov bl, [byte cs:di]
	xor al, bl
	and al, 1110b ; 14 - color value
	mov [color], al
	ret
endp GenerateValues
proc InitMouse
	; Initialize mouse
	mov ax, 0h
	int 33h
	mov ax, 1h
	int 33h
	ret
endp InitMouse
proc WaitForSquareClick
	; Waits 1 second totally. if mouse clicked on square - great, make sound and add points
	mov ax, [clock]
	; calculate how many ticks will be after 1 second past
	add ax, 18 ; 18x0.55=0.99secs
	mov [reqClock], ax ; and store the value
	UntilSecondPast:
		mov ax, [clock]
		cmp ax, [reqClock]
		jge WaitForSquareClick_end ; 1 second past, stop checking
		
		mov ax, 3h
		int 33h
		cmp bx, 01b
		jne UntilSecondPast ; not clicked
		mov bh, 0h
		mov ah, 0dh
		int 10h
		cmp al, [color]
		jne UntilSecondPast ; or color doesn't match
		
	WaitForSquareClick_end:
	ret
endp
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
	mov cx, [repeats]
	MainLoop:
		call GenerateValues ; generate the random values for x, y and color
		call DrawSquare ; draw square at (x,y) and by the color
		call WaitForSquareClick
		dec [repeats]
		cmp [repeats], 0
		jge MainLoop
		
	WaitForKeypress:
		mov ah, 0bh
		int 21h      ;RETURNS AL=0 : NO KEY PRESSED, AL!=0 : KEY PRESSED.
		cmp al, 0
		je  WaitForKeypress	
    ; Back to text mode
    mov ah, 0
    mov al, 2
    int 10h

exit :
mov ax, 4c00h
int 21h
END start



