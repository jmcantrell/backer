#!/bin/bash

# Filename:      backer.sh
# Description:   Backup data with rsync using profiles and email notification.
# Maintainer:    Jeremy Cantrell <jmcantrell@gmail.com>
# Last Modified: Fri 2010-04-23 12:47:05 (-0400)

# There's nothing all that special going on here beyond an "rsync -azv"
# command. It's based on profiles, so many complex rsync commands can be
# constructed and recalled easily. A notification email can be sent
# (optionally, with a log file). Log files can be stored in a directory.

# IMPORTS {{{1

source bashful-files
source bashful-messages
source bashful-modes
source bashful-profile
source bashful-utils

# FUNCTIONS {{{1

backup() #{{{2
{
    if [[ $log_directory ]]; then
        log=$log_directory/$PROFILE-$(date +%Y%m%d%H%M%S).log
    fi

    local mount
    for p in 'source' 'destination'; do
        mount=$(named "${p}_mount")
        if [[ $mount ]]; then
            if ! mounted_path "$mount"; then
                error "$(title <<<"$p") not mounted."
                return 1
            fi
        fi
    done

    info -c "Backing up '$source' to '$destination'..."

    local exclude_file=$CONFIG_DIR/excludes/$PROFILE

    if [[ ! -f $exclude_file ]]; then
        mkdir -p "$CONFIG_DIR/excludes"
        touch $exclude_file
    fi

    tempfile || return 1
    cat "$exclude_file" >$TEMPFILE
    exclude_file=$TEMPFILE

    local command=(
        rsync -azv $DRY_RUN --delete
        --exclude-from="$exclude_file"
        )

    for m in $(mount | awk '{print $3}'); do
        if [[ $m == $source/* ]]; then
            echo "$m" >>$exclude_file
        fi
    done

    command=("${command[@]}" "$source" "$destination")

    local error_occorred=0

    tempfile; local mail_file=$TEMPFILE

    if [[ $log_directory ]]; then
        "${command[@]}" >$log 2>>$mail_file || error_occurred=1
        local log_name=${log##*/}
        tempfile -d; local log_zip=$TEMPFILE/$log_name.gz
        gzip -c "$log" >$log_zip
        echo "Attached log: $log_name" >>$mail_file
    else
        verbose_execute "${command[@]}" || error_occorred=1
    fi

    if [[ $email ]]; then
        if truth $email_on_error && ! truth $error_occorred; then
            return 0
        fi
        info -c "Notifying '$email'..."
        local subject="Backup for $HOSTNAME on $(date +%Y-%m-%d)"
        if type mimemail &>/dev/null; then
            mimemail -s "$subject" -t "$email" "$log_zip" <$mail_file
        elif type mail &>/dev/null; then
            mail -s "$subject" "$email" <$mail_file
        fi
    fi
}

# VARIABLES {{{1

SCRIPT_NAME=$(basename "$0" .sh)
SCRIPT_USAGE="Backup data using rsync."
SCRIPT_OPTS="
-n              Dry run.

-C DIRECTORY    Use DIRECTORY for configuration.

-P PROFILE      Use PROFILE for action.
-N              Create new profile.
-L              List profiles.
-D              Delete profile.
-E              Edit profile.
"

interactive ${INTERACTIVE:-0}
verbose     ${VERBOSE:-0}

# PROFILE VARIABLES {{{1

PROFILE_DEFAULT="
source=/home/
destination=/media/backup/home/
# source_mount=/home
# destination_mount=/media/backup
# email=joe@example.org
# email_on_error=1
# log_directory=/media/backup/log
"

profile_init || die "Could not initialize profiles."

# COMMAND-LINE OPTIONS {{{1

unset OPTIND
while getopts ":hifvqnC:P:NLDE" option; do
    case $option in
        C) CONFIG_DIR=$OPTARG ;;

        P) PROFILE=$OPTARG ;;
        N) PROFILE_ACTION=create ;;
        L) PROFILE_ACTION=list ;;
        D) PROFILE_ACTION=delete ;;
        E) PROFILE_ACTION=edit ;;

        n) DRY_RUN=-n ;;

        i) interactive 1 ;;
        f) interactive 0 ;;

        v) verbose 1 ;;
        q) verbose 0 ;;

        h) usage 0 ;;
        *) usage 1 ;;
    esac
done && shift $(($OPTIND - 1))

# PROFILE ACTIONS {{{1

if [[ $PROFILE_ACTION ]]; then
    if ! profile_$PROFILE_ACTION; then
        die "Could not $PROFILE_ACTION profile(s)."
    fi
    exit 0
fi

# PROFILE CONTENT ACTIONS {{{1

OIFS=$IFS; IFS=$'\n'
for PROFILE in $(profile_list "$PROFILE"); do
    IFS=$OIFS

    profile_load || die   "Could not load profile '$PROFILE'."
    backup       || error "Could not backup profile '$PROFILE'."

done
