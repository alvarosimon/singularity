#!/bin/bash
# Script to syncronize users with system singularity group

vsc_group="gsingularity"
singularity_group="singularity"

# Clean singularity group
clean_singularity_group (){
    for user in $(/usr/bin/getent group "$singularity_group" | cut -d ':' -f 4 | tr ',' ' '); do
        # Detect user groups and allow $vsc_group
        if /usr/bin/id -nG "$user"| /usr/bin/grep -qw "$vsc_group"; then
            echo "$user still belongs to $vsc_group group"
        else
            echo "$user does not belong to $vsc_group group anymore" >&2
            /usr/bin/gpasswd -d "$user" "$singularity_group" >& /dev/null
        fi
    done
}


clean_singularity_group
# Add vsc singularity users to group
for user in $(/usr/bin/getent group "$vsc_group"| cut -d ':' -f 4 | tr ',' ' '); do
    /usr/bin/gpasswd -a "$user" "$singularity_group"
done
