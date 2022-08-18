#!/bin/bash
# 
#  
#
# 2022-02-25 the goal here is to have a bitwarden entry specify all the
# information entry to connect to an ssh host.
#
# The following bitwarden custome fields are recognized by this script:
# - ssh_host
#
# - ssh_username
#
# - ssh_port
#
# - ssh_private_key_reference This can take one of several possible forms:
#   
#   (empty or nonexistent) : In this case, we assume that the private key is
#   contained in a file, named "id_rsa", attached to the current bitwarden item
#   (or that we can keep following chains of ssh_private_key_reference until
#   eventually we hit such an item (not yet implemented.  TODO))
#   
#   a truthy string: In this case, we take the string as a the id of a bitwarden
#   item, and we fetch the file name "id_rsa" attached to that bitwarden item.
#   
#   TODO: allow to specify the signature of a private key that we will look for
#   elsewhere.
#
# Examples:
#
# # establish an ssh session:
# env 'U:\scripting_journal\2022-02-25-1352_ssh_session_nailed_up.sh' 'openwrt router neil'
#
# # do an scp file transfer:
# env 'U:\scripting_journal\2022-02-25-1352_ssh_session_nailed_up.sh' 'openwrt router neil' scp "\${sshHost}:/lib/netifd/hostapd.sh" "./hostapd.sh"
#
# I suspect that I might be reinventing parts of ssh-agent's behavior here .


idOfBitwardenItem="$1"

#we whant businessCommandSpecification to be an array of strings, consisting of all the commandline arguments following the first command line argument
businessCommandSpecification=( "${@:2}" )


# businessExecutable="${businessCommandSpecification[0]}"
# echo "\$#: $#"
# echo "\${#businessCommandSpecification[@]}: ${#businessCommandSpecification[@]}"
# echo "\${businessCommandSpecification[@]}: ${businessCommandSpecification[@]}"
# echo "businessExecutable: ${businessExecutable}"
# echo "length of businessExecutable: ${#businessExecutable}"


# eventually, I would like this script to be a wrapper around any arbitrary
# scp-like or ssh-like program (primarily ssh and scp, which take very similar
# argumnets) This script will look up the authentitcation information from the
# bitwarden database, then run the command that the user specifies , which is
# assumed to accept scp/ssh-like arguments to specify the authentication
# details.  I am hoping that scp can be called like this:
#   scp <all information that needs to be looked up in bitwarden goes here>  <non-authentication-related arguments>
#
# Hence, the "executable" argument.

if [ -z "$idOfBitwardenItem" ] ; then : ;
    # hard-coding temporarily for backwards compatibility.
    # unset idOfBitwardenItemContainingThePrivateKey

    # #unifi server:
    # idOfBitwardenItem="autoscan unifi server linux credentials"; 


    # # #autoscan router1:
    # idOfBitwardenItem="02ab7979-6c58-4cbe-bfc5-a9ba002ef4d7";  

    # #autoscan router3:
    idOfBitwardenItem="ef8933bd-9342-40ea-bc30-ae45017c4071";  
fi;
echo "idOfBitwardenItem: ${idOfBitwardenItem}" 1>&2



#


getFieldOfBitwardenItem(){
    local bitwardenItem="$1"
    local nameOfField="$2"
    local valueOfField="$(echo "${bitwardenItem}" | jq --raw-output ".fields | map(select(.name == \"${nameOfField}\")) | .[0] | .value + \"\"")"
    echo -n "${valueOfField}"
}


getFieldOfBitwardenItemById(){
    local idOfBitwardenItem="$1"
    local nameOfField="$2"

    local bitwardenItem=$(bw --raw get item "${idOfBitwardenItem}")
    getFieldOfLiteralBitwardenItem "$bitwardenItem" "$nameOfField"
}


getHostnameFromUri(){
    local uri="$1"
    local uriPattern
    local cleanedUriPattern
    local sedScript
    uriPattern="$(cat << 'EOL'
^
(
([a-z][a-z0-9+.-]*)
:\/\/
)?
(([a-z0-9._~%!$&'()*+,;=-]+)@)?
([a-z0-9._~%-]+|\[[a-f0-9:.]+\]|\[v[a-f0-9][a-z0-9._~%!$&'()*+,;=:-]+\])
(:([0-9]+))?
\/?.*
$
EOL
)"
    cleanedUriPattern="$( echo "$uriPattern" | tr -d "\n" )"

    # subpatterns
    # 1: scheme
    # 2: 
    # 3: user
    # 4: host
    # 5: 
    # 6: port`
    sedScript="s/${cleanedUriPattern}/\\5/"
    echo -n "$uri" | sed -E "$sedScript"
}

bitwardenItem=$(bw --raw get item "${idOfBitwardenItem}")

sshHostCandidates=( )


sshHostFieldContents="$(getFieldOfBitwardenItem "${bitwardenItem}" ssh_host)"
if [[ ! ( -z "$sshHostFieldContents" ) ]] ; then : ;
    sshHostCandidates[${#sshHostCandidates[@]}]="$sshHostFieldContents"
fi;


for uri in $(echo "${bitwardenItem}" | jq --raw-output ".login.uris[].uri"); do : ;
    hostname="$(getHostnameFromUri "${uri}")"
    
    if [[ ! ( -z "$hostname" ) ]] ; then : ;
        sshHostCandidates[${#sshHostCandidates[@]}]="$hostname"
    fi;
done;

#TODO: remove duplicates from sshHostCandidates

sshHost=${sshHostCandidates[0]}

echo "sshHost: ${sshHost}" 1>&2
echo "sshHostCandidates: ${sshHostCandidates[@]}" 1>&2

sshUsername="$(getFieldOfBitwardenItem "${bitwardenItem}" ssh_username)"
if [ -z "$sshUsername" ] ; then : ;
    # sshUsername="$(bw --raw get username "$idOfBitwardenItem")"
    sshUsername=$(echo "${bitwardenItem}" | jq --raw-output ".login.username")
fi;
echo "sshUsername: ${sshUsername}" 1>&2

sshPort="$(getFieldOfBitwardenItem "${bitwardenItem}" ssh_port)"
echo "sshPort: ${sshPort}" 1>&2

sshPrivateKeyReference="$(getFieldOfBitwardenItem "${bitwardenItem}" ssh_private_key_reference)"
echo "sshPrivateKeyReference: ${sshPrivateKeyReference}" 1>&2



if [ -z "$sshPrivateKeyReference" ] ; then : ;
    idOfBitwardenItemContainingThePrivateKey="$idOfBitwardenItem"
else : ;
    idOfBitwardenItemContainingThePrivateKey="$sshPrivateKeyReference"
fi;
echo "idOfBitwardenItemContainingThePrivateKey: ${idOfBitwardenItemContainingThePrivateKey}" 1>&2
sshPrivateKey="$(bw --raw get attachment "id_rsa" --itemid "$idOfBitwardenItemContainingThePrivateKey")"
if [ -z "${sshPrivateKey}" ] ; then : ;
    echo "warning: ssh_private_key is empty." 1>&2
else : ;
    echo "ssh_private_key is present." 1>&2
fi;


sshConfigurationOptionArgs=(
    -o StrictHostKeyChecking=no 

    -o PubkeyAcceptedKeyTypes=+ssh-rsa 
    -o HostKeyAlgorithms=+ssh-rsa
    #temporary work-around for sophos router (I might need to replace my
    # favorite keypair  with a new one that does not rely on the now-deprecated
    # SHA-1 hash algorithm (although I am not entirely sure how the key pair
    # depends on the hash algorithm) -- the source of the dependency might be
    # the hash that is stored by the server in the authorized keys list.
    # possibly, I merely need to recompute a different hash of my public key and
    # store this different hash in the the server. see
    # https://www.openssh.com/txt/release-8.2

    -o ServerAliveInterval=5

    $(
        if ! [[ -z "${sshPort}" ]]; then : ; 
            echo -n "-o Port=${sshPort}";  
        fi;
    )

    -o User="${sshUsername}"

    -o HostName="${sshHost}"
)

# pathOfTempSshConfigFile="$(mktemp)"
# > "$pathOfTempSshConfigFile" cat << EOL 
#     StrictHostKeyChecking=no
#     PubkeyAcceptedKeyTypes=+ssh-rsa
#     ServerAliveInterval=14
#     $(
#         if ! [[ -z "$sshPort" ]]; then : ; 
#             echo "Port=$sshPort";  
#         fi;
#     )
#     User=$sshUsername
#     HostName=$sshHost
#     #include the standard per-user config file
#     include config
# EOL
# chmod u=rw "$pathOfTempSshConfigFile"
#the above chmod ensures that the permissions for the tempssh file 
# satisfy ssh's stringent requirements.


echo "length of sshConfigurationOptionArgs: ${#sshConfigurationOptionArgs[@]}" 1>&2


# businessCommand will be run in an environment in which the variables sshOptions and sshHost are defined.
sshOptions="${sshConfigurationOptionArgs[@]}"

if [[ "${#businessCommandSpecification[@]}" == "0" ]]; then : ;
    businessCommand="ssh $sshOptions ''"
    # the last argument to ssh, above, is a dummy hostname, as required by ssh
    # command line syntax (in this case just an empty string).
else : ;
    businessCommand="${businessCommandSpecification[@]}"
fi;

echo "businessCommand: ${businessCommand}" 1>&2

nailedUpLoopCommand=$(cat << EOF
result=1
# trap "echo received INT 1>&2 ; kill \$(jobs -p); exit;" INT
trap "echo received INT 1>&2 ; exit;" INT

while true ; do : ;
    echo "now running: "${businessCommand@Q}  1>&2
    sshHost=${sshHost@Q}; sshOptions=${sshOptions@Q}; ${businessCommand} ;
    result=\$?
    if [ \$result -eq 0 ] ; then : ;
        echo "business command exited with exit code \$result, so we will not attempt to rerun business command. " 1>&2;
        break;
    else 
        echo "business command exited with exit code \$result, so we will attempt to rerun business command. " 1>&2
        waitTime=5
        echo "waiting \$waitTime seconds before attempting to rerun business command." 1>&2
        sleep 5
    fi;
done;
EOF
)

#TODO - handle the various termination signals so that we can press Ctrl-C during the 5 seocnd wait and not be left in the shell.
# This seems to be accomplished by having added the trap... command above.

keyLoadingCommand="ssh-add <(echo \"${sshPrivateKey}\")"
initCommand=$(cat << EOF
#!/bin/bash
${keyLoadingCommand}
${nailedUpLoopCommand}
exit;
EOF
)


echo "now running ssh-agent" 1>&2

echo "\$-: $-" 1>&2

case "$-" in
*i*)	echo This shell is interactive  1>&2 ;;
*)	echo This shell is not interactive  1>&2 ;;
esac

# # # case "$-" in
# # # *i*)	echo This shell is interactive  1>&2 ; ssh-agent bash --init-file <($(cat ~/.bashrc); echo ""; echo "${initCommand}")  ;;
# # # *)	echo This shell is not interactive  1>&2 ; ssh-agent bash <(echo "${initCommand}") ;;
# # # esac

#I am not fully comprehending this business about an interactive shell.
# for now, I will simply force interactive mode using the -i options
# ssh-agent bash --init-file <($(cat ~/.bashrc); echo ""; echo "${initCommand}") -i  
# ssh-agent bash --init-file <( cat ~/.bashrc ; echo "" ; echo "${initCommand}" )  -i
# ssh-agent bash -i -o ignoreeof <( cat ~/.bashrc ; echo "" ; echo "${initCommand}" )
ssh-agent bash <( echo "${initCommand}" )
