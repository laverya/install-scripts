
#######################################
#
# prompt.sh
#
#######################################

PROMPT_RESULT=
READ_TIMEOUT="-t 20"

#######################################
# Confirmation prompt default yes.
# Globals:
#   READ_TIMEOUT
# Arguments:
#   None
# Returns:
#   None
#######################################
confirmY() {
    printf "(Y/n) "
    set +e
    read $READ_TIMEOUT _confirm < /dev/tty
    set -e
    if [ "$_confirm" = "n" ] || [ "$_confirm" = "N" ]; then
        return 1
    fi
    return 0
}

#######################################
# Confirmation prompt default no.
# Globals:
#   READ_TIMEOUT
# Arguments:
#   None
# Returns:
#   None
#######################################
confirmN() {
    printf "(y/N) "
    set +e
    read $READ_TIMEOUT _confirm < /dev/tty
    set -e
    if [ "$_confirm" = "y" ] || [ "$_confirm" = "Y" ]; then
        return 0
    fi
    return 1
}


#######################################
# Prompts the user for input.
# Globals:
#   READ_TIMEOUT
# Arguments:
#   None
# Returns:
#   PROMPT_RESULT
#######################################
prompt() {
    set +e
    read PROMPT_RESULT < /dev/tty
    set -e
}

#######################################
# Prompts the user for input.
# Globals:
#   READ_TIMEOUT
# Arguments:
#   None
# Returns:
#   PROMPT_RESULT
#######################################
promptTimeout() {
    set +e
    read ${1:-$READ_TIMEOUT} PROMPT_RESULT < /dev/tty
    set -e
}
