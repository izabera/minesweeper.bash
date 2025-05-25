die () { lastmsg=$*; exit 1; }
lastmsg () { echo "$lastmsg" >&2; }
trap lastmsg exit

W=${W-9} H=${H-9} BOMBS=${BOMBS-10}
(( (size = W*H) < 2**15 )) || die board too big

# x  |32  uncovered
# x  |64  flag

# 0-9     not bombs (covered)
# 0-9|32  not bombs (uncovered)
# 0-9|64  flagged non bomb (you fucked up)

# 10      bomb (covered)
# 10 |32  bomb (uncovered) (you fucked up badly)
# 10 |64  flagged bomb

in_bounds () (( $1 >= 0 && $1 < H && $2 >= 0 && $2 < W ))
surrounding () {
    local i j
    for (( i = -1; i <= 1; i++ )) do
        for (( j = -1; j <= 1; j++ )) do
            (( i != 0 || j != 0 )) &&
            in_bounds "$(($1+i))" "$(($2+j))" &&
            "$3" "$(($1+i))" "$(($2+j))"
        done
    done
}

fillboard () {
    local I=$1 J=$2 i j
    board=()
    for (( i = 0; i < BOMBS; )) do
        (((r = RANDOM % size) != I*W+J)) && ((board[r]=10,i++))
    done

    addvalue () (( value += board[$1*W+$2] == 10 ))
    for (( i = 0; i < H; i++ )) do
        for (( j = 0; j < W; j++ )) do
            (( board[i*W+j] == 10 )) && continue
            value=0
            surrounding "$i" "$j" addvalue
            board[i*W+j]=$value
        done
    done
}

colours=([1]=27 [2]=28 [3]=160 [4]=20 [5]=88 [6]=38 [7]=232 [8]=240)

boardgen=0 face=':)'
draw () {
    printf '\e8\e7'
    for (( i = 0; i < H; i++ )) do
        for (( j = 0; j < W; j++ )) do
            if (( board[i*W+j] & 32 )); then # uncovered
                case $((board[i*W+j] & 0xf)) in
                    10) printf '\e[48;5;250;38;5;196mBB' ;;
                    0)  printf '\e[48;5;250m  ' ;;
                    *)  printf '\e[48;5;250;38;5;%sm%2s' "${colours[board[i*W+j]&0xf]}" "$((board[i*W+j]&0xf))" ;;
                esac
            elif (( board[i*W+j] & 64 )); then # covered and flagged
                printf '\e[48;5;243;38;5;196mFF'
            else # covered and unknown
                printf '\e[48;5;243m  '
            fi
            printf '\e[m'
        done
        printf '\n'
    done
    printf '\e[48;5;220;38;5;232m%s\e[m' "$face"
}



[[ -t 0 && -t 1 ]] || die this is not a terminal

printf '\e[?%s' 1049h 1000h 1006h 25l
trap 'printf \\e[?%s 1049l 1000l 1006l 25h; stty echo sane; lastmsg' exit
printf '\e7'

LANG=C
shopt -s extglob
stty -echo

mouseregex=$'\e\[<([0-9]+);([0-9]+);([0-9]+)([mM])'
getinput() {
    while read -rn1; do
        __input+=$REPLY
        case $__input in
            $'\3'*) exit ;; # ^C
            $'\e[<'+([0-9;])[mM])
                [[ $__input =~ $mouseregex ]]
                BUTTON=("${BASH_REMATCH[@]:1:4}")
                __input=
                break 2
                ;;
            # csi/ss3 arrows | non csi escape | weird csi
            $'\e'[[O][ABCD]  | $'\e'[^[]      | $'\e['*([0-?])*([ -/])[@-~]) __input=;;
            $'\e'*) ;; # incomplete csi
            *) __input= ;; # weird keyboard input?
        esac
    done
}



printf -v line '%*s' "$W"
line='|'${line// /%2s|}$'\n'

addqueue () { queue+=("$1" "$2"); }
openzeros() {
    local I J i j queue=("$1" "$2")
    while (( ${#queue[@]} )); do
        i=${queue[0]} j=${queue[1]} queue=("${queue[@]:2}")
        (( (${board[i*W+j]} & (32|0xf)) == 0 )) && surrounding "$i" "$j" addqueue
        (( board[i*W+j] |= 32 ))
    done
}

while draw; getinput; do
    (( I=BUTTON[2]-1, J=(BUTTON[1]-1)/2 ))
    [[ ${BUTTON[3]} == M ]] || continue
    if (( I == H && J == 0 )); then
        face=':)'
        board=()
        boardgen=0
        continue
    fi
    [[ $face == ':)' ]] || continue
    (( I*W+J < size )) || continue

    (( !boardgen++ )) && fillboard "$I" "$J"

    (( BUTTON == 2 && (board[I*W+J] ^= 64) ))
    if (( BUTTON == 0 && (board[I*W+J] & (32|0xf)) == 0 )); then
        openzeros "$I" "$J"
    fi

    (( BUTTON == 0 && (board[I*W+J] |= 32) ))
    if (( (board[I*W+J] & (32|0xf)) == (32|10) )); then # you just uncovered a bomb
        face=':('
        for (( i = 0; i < W*H; i++ )) do
            (( board[i] & 0xf == 10 && (board[i] |= 32) ))
        done
    fi

    #set -x
    # check if any non bombs are left
    for (( i = 0; i < W*H; i++ )) do
        : i=$i "${board[i]}"
        (( (board[i] & 0xf) == 10 )) && continue
        (( board[i] & 32 )) || {
            set +x
            continue 2
        }
    done
    set +x
    for (( i = 0; i < W*H; i++ )) do
        (( (board[i] & 0xf) == 10 )) && (( board[i] |= 64 ))
    done
    face='8)'
done
