#!/bin/bash

# Script is brought to you by ATADA Stakepool, Telegram @atada_stakepool

#load variables and functions from common.sh
. "$(dirname "$0")"/00_common.sh


#Display usage instructions
showUsage() {
cat >&2 <<EOF

Catalyst FUND-10 Special Version

Usage: $(basename $0) new cli <voteKeyName>                          ... Generates a new 24-Words-Mnemonic and derives the VotingKeyPair with the given name
       $(basename $0) new cli <voteKeyName> "<24-words-mnenonics>"   ... Generates a new VotingKeyPair with the given name from an existing 24-Words-Mnemonic

       $(basename $0) genmeta <delegate_to_voteKeyName|voteBechPublicKey> <stakeAccountName> <rewardsPayoutPaymentName or bech adress>
          ... Generates the Catalyst-Registration-Metadata(cbor) to delegate the full VotingPower of the given stakeAccountName to the voteKeyName
              or votePublicKey, rewards will be paid out to the rewardsPayoutPaymentName
              ! In case you wanna use a HW-Wallet, be sure to also use a rewardsPayoutAddress on the HW-Wallet itself !

       $(basename $0) qrcode <voteKeyName> <4-Digit-PinCode>         ... Shows the QR code for the Catalyst-Voting-App protected via a 4-digit PinCode

Examples:

       $(basename $0) new cli myvote
          ... Generates a new VotingKeyPair myvote.voting.skey/vkey, writes Mnemonics to myvote.voting.mnemonics

       $(basename $0) genmeta myvote owner myrewards
          ... Generates the Catalyst-Registration-Metadata(cbor) to delegate the full VotingPower of owner.staking to the myvote.voting votePublicKey,
              VotingRewards payout to the Address myrewards.addr.

       $(basename $0) genmeta myvote myLedger myLedger.payment
          ... Generates the Catalyst-Registration-Metadata(cbor) to delegate the full VotingPower of myLedger.staking.hwsfile to the myvote.voting votePublicKey,
              VotingRewards payout to the same HW-Wallet myLedger.payment.hwsfile.

       $(basename $0) qrcode myvote 1234
          ... Shows the QR code for the VotingKey 'myvote' and protects it with the PinCode '1234'. This QR code can be scanned
              with the Catalyst-Voting-App on your mobile phone if you don't wanna use the Catalyst-Voting-Center

EOF
}

accountNo=0 #set default accountNo
indexNo=0 #set default indexNo
payPath=0 #set default paymentPath

################################################
# MAIN START
#
# Check commandline parameters
#
paramCnt=$#;
allParameters=( "$@" )

if [[ ${paramCnt} -lt 3 ]]; then showUsage; exit 1; fi

case ${1,,} in

  ### Generate the QR code from the vote secret key for the mobile voting app
  qrcode )

		#Check the catalyst-toolbox binary existance and version
		if ! exists "${catalyst_toolbox_bin}"; then
                                #Try the one in the scripts folder
                                if [[ -f "${scriptDir}/catalyst-toolbox" ]]; then catalyst_toolbox_bin="${scriptDir}/catalyst-toolbox";
                                else majorError "Path ERROR - Path to the 'catalyst-toolbox' binary is not correct or 'catalyst-toolbox' binaryfile is missing!\nYou can find it here: https://github.com/input-output-hk/catalyst-toolbox/releases/latest \nThis is needed to generate the QR code for the Catalyst-App. Also please check your 00_common.sh or common.inc settings."; exit 1; fi
		fi
		catalystToolboxCheck=$(${catalyst_toolbox_bin} --version 2> /dev/null)
		if [[ $? -ne 0 ]]; then echo -e "\e[35mERROR - This script needs a working 'catalyst-toolbox' binary. Please make sure you have it present with with the right path in '00_common.sh' !\e[0m\n\n"; exit 1; fi
		catalystToolboxVersion=$(echo ${catalystToolboxCheck} | cut -d' ' -f 2)
		versionCheck "${minCatalystToolboxVersion}" "${catalystToolboxVersion}"
		if [[ $? -ne 0 ]]; then majorError "Version ${catalystToolboxVersion} ERROR - Please use a cardano-toolbox version ${minCatalystToolboxVersion} or higher !\nOld versions are not compatible, please upgrade - thx."; exit 1; fi

                voteKeyName="${allParameters[1]}"; voteKeyName=${voteKeyName/#.\//};
		pinCode="${allParameters[2]}";
                if [ ! -f "${voteKeyName}.voting.skey" ]; then echo -e "\e[35mError - ${voteKeyName}.voting.skey is missing, please generate it first with the subcommand 'new' !\e[0m\n"; showUsage; exit 1; fi
                if [ -z "${pinCode##*[!0-9]*}" ] || [ ${#pinCode} -lt 4 ] || [ ${pinCode} -lt 0 ] || [ ${pinCode} -gt 9999 ]; then echo -e "\e[35mError - The PinCode must be a 4-Digit-Number between 0000 and 9999 !\e[0m\n"; exit 1; fi
                if [ -f "${voteKeyName}.catalyst-qrcode.png" ]; then echo -e "\e[35mError - ${voteKeyName}.catalyst-qrcode.png already exists, please delete it first if you wanna overwrite it !\e[0m\n"; exit 1; fi

                echo -e "\e[0mGenerating the Catalyst-Voting-App QR Code for the Voting-Signing-Key: \e[32m${voteKeyName}.voting.skey\e[0m"
                echo
                echo -e "\e[0mYour Pin-Code for the Catalyst-APP: \e[32m${pinCode}\e[0m"
                echo

		#Read in the ${voteKeyName}.voting.skey and check that it is a valid json keyfile with a key in the cborHex entry and not the old bech format
		skeyJSON=$(read_skeyFILE "${voteKeyName}.voting.skey"); if [ $? -ne 0 ]; then echo -e "\e[35m${skeyJSON}\e[0m\n"; exit 1; else echo -e "\e[32mOK\e[0m\n"; fi
		cborVoteKey=$(jq -r ".cborHex" <<< "${skeyJSON}" 2> /dev/null);
		if [[ $? -ne 0 ]]; then echo -e "\e[35mERROR - ${voteKeyName}.voting.skey is not a valid json file. Please make sure to use the new voting key format, you can generate it with the subcommand 'new' !\e[0m\n\n"; exit 1; fi
		unset skeyJSON

		#Generate the voting key bech format for catalyst toolbox
		bechVoteKey=$(cut -c 5-132 <<< ${cborVoteKey} | ${bech32_bin} "ed25519e_sk" 2> /dev/null)
                checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
		unset cborVoteKey

		#Generate the QR code by passing on the bechVoteKey "as a file" to catalyst toolbox
		echo -e "\e[0mGenerating with Cardano-Toolbox Version: \e[32m${catalystToolboxVersion}\e[0m\n";
                tmp=$(${catalyst_toolbox_bin} qr-code encode --pin ${pinCode} --input <(echo -n ${bechVoteKey}) --output ${voteKeyName}.catalyst-qrcode.png img)
                checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
                file_lock ${voteKeyName}.voting.skey
                echo -e "\e[0mCatalyst-QR-Code: \e[32m ${voteKeyName}.catalyst-qrcode.png \e[0m"
                ${catalyst_toolbox_bin} qr-code encode --pin ${pinCode} --input <(echo -n ${bechVoteKey}) img
                echo
		unset bechVoteKey

		echo -e "\e[33mIf you use this QR code with the Catalyst-Voting-App, please only vote with the Catalyst-Voting-App and not also with the Catalyst-Voting-Center. Thx!\e[0m\n";

                exit 0;
                ;;


  ### Generate new Voting Keys
  new )
                if [[ ${paramCnt} -ge 3 ]]; then
			method="${allParameters[1]}";
			voteKeyName="${allParameters[2]}"; voteKeyName=${voteKeyName/#.\//};
		else echo -e "\e[35mMissing parameters!\e[0m\n"; showUsage; exit 1; fi

		if [ -f "${voteKeyName}.voting.vkey" ]; then echo -e "\e[35mError - ${voteKeyName}.voting.vkey already exists, please delete it first if you wanna overwrite it !\e[0m\n"; exit 1; fi
		if [ -f "${voteKeyName}.voting.skey" ]; then echo -e "\e[35mError - ${voteKeyName}.voting.skey already exists, please delete it first if you wanna overwrite it !\e[0m\n"; exit 1; fi
		if [ -f "${voteKeyName}.voting.hwsfile" ]; then echo -e "\e[35mError - ${voteKeyName}.voting.hwsfile already exists, please delete it first if you wanna overwrite it !\e[0m\n"; exit 1; fi

                echo -e "\e[0mGenerating a new Voting-KeyPair with the name: \e[32m${voteKeyName}\e[0m"
		echo
		echo -e "\e[0mDeriving Voting-Keys from path:\e[32m 1694H/1815H/${accountNo}H/${payPath}/${indexNo}\e[0m"
		echo

		#Getting the Voting Key Pair via CLI or via HW-Wallet

		case ${method,,} in

		   cli )

			#Check the cardano-signer binary existance and version
			if ! exists "${cardanosigner}"; then
                                #Try the one in the scripts folder
                                if [[ -f "${scriptDir}/cardano-signer" ]]; then cardanosigner="${scriptDir}/cardano-signer";
                                else majorError "Path ERROR - Path to the 'cardano-signer' binary is not correct or 'cardano-singer' binaryfile is missing!\nYou can find it here: https://github.com/gitmachtl/cardano-signer/releases\nThis is needed to generate the signed Metadata. Also please check your 00_common.sh or common.inc settings."; exit 1; fi
			fi
			cardanosignerCheck=$(${cardanosigner} --version 2> /dev/null)
			if [[ $? -ne 0 ]]; then echo -e "\e[35mERROR - This script needs a working 'cardano-signer' binary. Please make sure you have it present with with the right path in '00_common.sh' !\e[0m\n\n"; exit 1; fi
			cardanosignerVersion=$(echo ${cardanosignerCheck} | cut -d' ' -f 2)
			versionCheck "${minCardanoSignerVersion}" "${cardanosignerVersion}"
			if [[ $? -ne 0 ]]; then majorError "Version ${cardanosignerVersion} ERROR - Please use a cardano-signer version ${minCardanoSignerVersion} or higher !\nOld versions are not compatible, please upgrade - thx."; exit 1; fi

			echo -e "\e[0mUsing Cardano-Signer Version: \e[32m${cardanosignerVersion}\e[0m\n";

	                if [[ ${paramCnt} -ge 4 ]]; then
				mnemonics="${allParameters[3]}" #read the mnemonics
				mnemonics=$(trimString "${mnemonics,,}") #convert to lowercase and trim it
				mnemonicsWordcount=$(wc -w <<< ${mnemonics})
				if [[ ${mnemonicsWordcount} -ne 24 ]]; then echo -e "\e[35mError - Please provide 24 Mnemonic Words, you've provided ${mnemonicsWordcount}!\e[0m\n"; exit 1; fi
			fi

			if [[ ${mnemonics} != "" ]]; then #use the provided mnemonics
				echo -e "\e[0mUsing Mnemonics:\e[32m ${mnemonics}\e[0m"
				#Generate the Vote-Key-Files with given mnemonics
				voteKeyJSON=$(${cardanosigner} keygen --cip36 --mnemonics "${mnemonics}" --json-extended --out-skey "${voteKeyName}.voting.skey" --out-vkey "${voteKeyName}.voting.vkey")
				checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
			else
				#Generate the Vote-Key-Files and new mnemonics
				voteKeyJSON=$(${cardanosigner} keygen --cip36 --json-extended --out-skey "${voteKeyName}.voting.skey" --out-vkey "${voteKeyName}.voting.vkey")
				checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
				mnemonics=$(jq -r ".mnemonics" <<< ${voteKeyJSON})
				echo -e "\e[0mCreated Mnemonics:\e[32m ${mnemonics}\e[0m"
			fi

			echo

			file_lock ${voteKeyName}.voting.skey
			echo -e "\e[0mVoting-Signing(Secret)-Key: \e[32m ${voteKeyName}.voting.skey \e[90m"
			cat "${voteKeyName}.voting.skey"
			echo -e "\e[0m"

	                file_lock ${voteKeyName}.voting.vkey
			echo -e "\e[0mVoting-Verification(Public)-Key: \e[32m ${voteKeyName}.voting.vkey \e[90m"
			cat "${voteKeyName}.voting.vkey"
			echo -e "\e[0m"

			#generate the vkey(publickey) also in the bech cvote_vk format, for other tools/usage
			vkeyBECH=$(jq -r .publicKeyBech <<< ${voteKeyJSON})
			checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
			echo "${vkeyBECH}" > "${voteKeyName}.voting.pkey" 2> /dev/null
			checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
	                file_lock ${voteKeyName}.voting.pkey
			echo -e "\e[0mVoting-Verification(Public)-Key Bech-Format: \e[32m ${voteKeyName}.voting.pkey \e[90m"
			cat "${voteKeyName}.voting.pkey"
			echo -e "\e[0m"

			#write out the used mnemonics
			echo "${mnemonics}" > "${voteKeyName}.voting.mnemonics" 2> /dev/null
			checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
			file_lock ${voteKeyName}.voting.mnemonics
			echo -e "\e[0mMnemonics-File: \e[32m ${voteKeyName}.voting.mnemonics\e[90m"
			cat "${voteKeyName}.voting.mnemonics"
			echo -e "\e[0m"

			exit 0;
			;; #cli


		   hw )

			#We need a voting keypair with vkey and hwsfile from a Hardware-Key, so lets create them
			start_HwWallet "" "6.0.3" ""; checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
			tmp=$(${cardanohwcli} address key-gen --path 1694H/1815H/${accountNo}H/${payPath}/${indexNo} --verification-key-file "${voteKeyName}.voting.vkey" --hw-signing-file "${voteKeyName}.voting.hwsfile" 2> /dev/stdout)
			if [[ "${tmp^^}" =~ (ERROR|DISCONNECT) ]]; then echo -e "\e[35m${tmp}\e[0m\n"; exit 1; else echo -e "\e[32mDONE\e[0m\n"; fi
			checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi

			#Set the right description according to CIP36
			hwsfileJSON=$(jq " .description = \"Hardware Catalyst Vote Signing File\" " "${voteKeyName}.voting.hwsfile")
			echo "${hwsfileJSON}" > "${voteKeyName}.voting.hwsfile" 2> /dev/null
			checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
		        file_lock "${voteKeyName}.voting.hwsfile"

			vkeyJSON=$(jq " .description = \"Hardware Catalyst Vote Verification Key\" " "${voteKeyName}.voting.vkey")
			echo "${vkeyJSON}" > "${voteKeyName}.voting.vkey" 2> /dev/null
			checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
		        file_lock "${voteKeyName}.voting.vkey"

			echo -e "\e[0mHardware-Voting-Signing-Key: \e[32m ${voteKeyName}.voting.hwsfile \e[90m"
			cat "${voteKeyName}.voting.hwsfile"
			echo
			echo
	                echo -e "\e[0mHardware-Voting-Public-Key: \e[32m ${voteKeyName}.voting.vkey \e[90m"
	                cat "${voteKeyName}.voting.vkey"
	                echo
			echo -e "\e[0m"

			exit 0;
			;; #hw

		   * )
			echo -e "\e[35mERROR - Method not supported. Please use 'cli' or 'hw' !\e[0m\n"; showUsage; exit 1;
			;;
		esac

                ;; #new




  ### Generate the registration metadata
  genmeta )

		#Check about 4 input parameters
		if [[ ${paramCnt} -ne 4 ]]; then echo -e "\e[35mIncorrect parameter count!\e[0m\n"; showUsage; exit 1; fi

		#Read the stakeAccount information
		stakeAcct="$(dirname ${allParameters[2]})/$(basename $(basename ${allParameters[2]} .addr) .staking).staking"; stakeAcct=${stakeAcct/#.\//};
		if ! [[ -f "${stakeAcct}.skey" || -f "${stakeAcct}.hwsfile" ]]; then echo -e "\n\e[35mERROR - \"${stakeAcct}.skey(hwsfile)\" Staking Signing Key or HardwareFile does not exist! Please create it first with script 03a.\e[0m"; exit 1; fi
		stakingName=$(basename ${stakeAcct} .staking) #contains the name before the .staking.addr extension

		#Output filename for the Voting-Registration-CBOR-Metadata
		datestr=$(date +"%y%m%d%H%M%S")
		votingMetaFile="${stakingName}_${datestr}.vote-registration.cbor"
		if [ -f "${votingMetaFile}" ]; then echo -e "\e[35mError - ${votingMetaFile} already exists, please delete it first if you wanna overwrite it !\e[0m\n"; exit 1; fi

                echo -e "\e[0mGenerating the Catalyst-Registration-MetadataFile(cbor): \e[32m${votingMetaFile}\e[0m"
                echo

		#Read the rewardsAcct information and generate a rewardsPayoutAddr
		rewardsAcct="$(dirname ${allParameters[3]})/$(basename ${allParameters[3]} .addr)"; rewardsAcct=${rewardsAcct/#.\//};

		if [ -f "${rewardsAcct}.addr" ]; then #address file found, read the content and check the type
			rewardsPayoutAddr=$(cat "${rewardsAcct}.addr" 2> /dev/null);
			#Check that the rewardsPayoutAddr is a valid PaymentAddress
			typeOfAddr=$(get_addressType "${rewardsPayoutAddr}"); checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi;
			if [[ ! ${typeOfAddr} == ${addrTypePayment} ]]; then echo -e "\n\e[35mERROR - \"${rewardsAcct}.addr\" does not contain a valid payment address!\e[0m"; exit 1; fi

                #check if its an root adahandle (without a @ char)
                elif checkAdaRootHandleFormat "${rewardsAcct}"; then
			addrName=${allParameters[3]}
                        if ${offlineMode}; then echo -e "\n\e[35mERROR - Adahandles are only supported in Online mode.\n\e[0m"; exit 1; fi
                        adahandleName=${addrName,,}
                        assetNameHex=$(convert_assetNameASCII2HEX ${adahandleName:1})
                        #query classic cip-25 adahandle asset holding address via koios
                        showProcessAnimation "Query Adahandle(CIP-25) into holding address: " &
                        response=$(curl -s -m 10 -X GET "${koiosAPI}/asset_address_list?_asset_policy=${adahandlePolicyID}&_asset_name=${assetNameHex}" -H "Accept: application/json" 2> /dev/null)
                        stopProcessAnimation;
                        #check if the received json only contains one entry in the array (will also not be 1 if not a valid json)
	                        if [[ $(jq ". | length" 2> /dev/null <<< ${response}) -ne 1 ]]; then
                                        #query classic cip-68 adahandle asset holding address via koios
                                        showProcessAnimation "Query Adahandle(CIP-68) into holding address: " &
                                        response=$(curl -s -m 10 -X GET "${koiosAPI}/asset_address_list?_asset_policy=${adahandlePolicyID}&_asset_name=000de140${assetNameHex}" -H "Accept: application/json" 2> /dev/null)
                                        stopProcessAnimation;
                                        #check if the received json only contains one entry in the array (will also not be 1 if not a valid json)
                                        if [[ $(jq ". | length" 2> /dev/null <<< ${response}) -ne 1 ]]; then echo -e "\n\e[35mCould not resolve Adahandle to an address.\n\e[0m"; exit 1; fi
                                        assetNameHex="000de140${assetNameHex}"
                                fi
                        addrName=$(jq -r ".[0].payment_address" <<< ${response} 2> /dev/null)
                        typeOfAddr=$(get_addressType "${addrName}");
                        if [[ ${typeOfAddr} != ${addrTypePayment} ]]; then echo -e "\n\e[35mERROR - Resolved address '${addrName}' is not a valid payment address.\n\e[0m"; exit 1; fi;
                        showProcessAnimation "Verify Adahandle is on resolved address: " &
                        utxo=$(${cardanocli} query utxo --address ${addrName} ${magicparam} ); stopProcessAnimation; checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi;
                        if [[ $(grep "${adahandlePolicyID}.${assetNameHex} " <<< ${utxo} | wc -l) -ne 1 ]]; then
                                echo -e "\n\e[35mERROR - Resolved address '${addrName}' does not hold the \$adahandle '${adahandleName}' !\n\e[0m"; exit 1; fi;
                        echo -e "\e[0mFound \$adahandle '${adahandleName}' on Address:\e[32m ${addrName}\e[0m\n"
			rewardsPayoutAddr=${addrName}


                elif checkAdaSubHandleFormat "${addrName}"; then
                        echo -e "\n\e[33mINFO - AdaSubHandles are not supported yet.\n\e[0m"; exit 1;


		else #try it as a direct payment bech address
			rewardsPayoutAddr=$(trimString "${allParameters[3]}")
			#Check that the rewardsPayoutAddr is a valid PaymentAddress
			typeOfAddr=$(get_addressType "${rewardsPayoutAddr}"); checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi;
			if [[ ! ${typeOfAddr} == ${addrTypePayment} ]]; then echo -e "\n\e[35mERROR - \"${rewardsAcct}.addr\" - file not found. Also it is not a direct valid payment address!\e[0m"; exit 1; fi
		fi

                echo -e "\e[0mStakeVotingPower will be registered/delegated to the following Voting-Public-Key(s):"
		echo

		#Read the votePublicKey informations - single or multiple with votingWeight values, separated via the | char
                #Split the parameter at the "|" char
                IFS='|' read -ra allVoteKeys <<< "${allParameters[1]}"

		defWeight=1 #if no voteWeight is provided, set it to the default weight of 1
		cardanoSignerParameters="" #holding variable for all the --vote-public-key as bechKey & --vote-weight parameters
		cardanoHwCliParameters="" #holding variable for all the --vote-public-key as file & --vote-weight parameters
                #Process each single given voteKeyName/votePublicKey
                for (( tmpCnt=0; tmpCnt<${#allVoteKeys[@]}; tmpCnt++ ))
                do
			IFS=' ' read -r voteKeyName voteKeyWeight <<< "${allVoteKeys[tmpCnt]}"
			voteKeyWeight=${voteKeyWeight:-"${defWeight}"} #set the voteWeight to the default value if nothing provided
			#check that the voteKeyWeight is a positive number
			if [ -z "${voteKeyWeight##*[!0-9]*}" ]; then echo -e "\n\e[35mERROR - The provided voteWeight of \"${voteKeyWeight}\" is not a pos. number!\e[0m"; exit 1; fi

			#check the voteKeyName entry if it is a .pkey file (contains the bech pubKey), or if is a .vkey file (contains the key in hex format) or if it is a direct bech or hex key
			if [ -f "${voteKeyName}.voting.pkey" ]; then #the .pkey file exists so lets read the value in it and check it if its a bech key
				inputKey=$(cat "${voteKeyName}.voting.pkey")
				tmp=$(${bech32_bin} <<< "${inputKey}" 2> /dev/null)
				if [ $? -ne 0 ]; then echo -e "\e[35mError - ${voteKeyName}.voting.pkey contains an invalid bech votePublicKey !\e[0m\n"; exit 1; fi
				votePubKey=$(${bech32_bin} "ed25519_pk" <<< "${inputKey}" 2> /dev/null) #make sure it is a bechKey "ed25519_pk"
				checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
				voteKeySource="${voteKeyName}.voting.pkey"
			elif [ -f "${voteKeyName}.voting.vkey" ]; then #the .vkey file exists so lets read the value in it and check it
				cborVoteKey=$(jq -r ".cborHex" "${voteKeyName}.voting.vkey" 2> /dev/null);
				if [[ $? -ne 0 ]]; then echo -e "\e[35mERROR - ${voteKeyName}.voting.vkey is not a valid json file. Please make sure to use the new voting key format, you can generate it with the subcommand 'new' !\e[0m\n\n"; exit 1; fi
				#Generate the voting key bech format
				inputKey=${cborVoteKey:4}
				votePubKey=$(${bech32_bin} "ed25519_pk" <<< ${inputKey:0:64} 2> /dev/null) #only use the first 64chars (32 bytes) in case an extended key was provided
				checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
				voteKeySource="${voteKeyName}.voting.vkey"

			elif [[ "${voteKeyName//[![:xdigit:]]}" == "${voteKeyName}" ]] && [[ ${#voteKeyName} -eq 64 || ${#voteKeyName} -eq 128 ]]; then #lets use a hex key as the voteKeyName with length of 32 or 64 bytes
				#Generate the voting key from hex input
				inputKey=${voteKeyName,,}
				votePubKey=$(${bech32_bin} "ed25519_pk" <<< ${inputKey:0:64} 2> /dev/null) #only use the first 64chars (32 bytes) in case an extended key was provided
				checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
				voteKeySource="direct"
				voteKeyName="Hex-VotePublicKey"

			else #ok lets try to read in the voteKeyName as a direct bech key
				inputKey="${voteKeyName}"
				tmp=$(${bech32_bin} <<< "${inputKey}" 2> /dev/null)
				if [ $? -ne 0 ]; then echo -e "\e[35mError - ${voteKeyName}.voting.pkey/vkey file not found. Also it is not a direct valid bech or hex votePublicKey !\e[0m\n"; exit 1; fi
				votePubKey=$(${bech32_bin} "ed25519_pk" <<< "${inputKey}" 2> /dev/null) #make sure it is a bechKey "ed25519_pk"
				checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
				voteKeySource="direct"
				voteKeyName="Bech-VotePublicKey"
			fi

			echo -e "\e[0m         Name: \e[32m${voteKeyName}\n\e[0m       Source: \e[32m${voteKeySource}\n\e[0m     inputKey: \e[32m${inputKey}\n\e[0m   votePubKey: \e[32m${votePubKey}\n\e[0m   voteWeight: \e[32m${voteKeyWeight}\e[0m\n"

			#building the parameterSet
			cardanoSignerParameters+="--vote-public-key ${votePubKey} --vote-weight ${voteKeyWeight} "

                done


		currentTip=$(get_currentTip) #we use the current slotHeight as the nonce parameter
		if [ $? -ne 0 ]; then exit $?; fi

		#add the reward address, nonce and networkmagic to the parameterSet
		cardanoSignerParameters+="--payment-address ${rewardsPayoutAddr} --nonce ${currentTip} ${magicparam} "
		cardanoHwCliParameters+="--reward-address ${rewardsPayoutAddr} --nonce ${currentTip} ${magicparam} "

		#If the StakeAccount is a HW-Wallet, do it all via cardano-hw-cli
		if [ -f "${stakeAcct}.hwsfile" ]; then

			#Check if the the rewardsPayout is done to the same HW-Wallet, if so include the --reward-address-signing-key parameter
			rewardsName=$(basename ${rewardsAcct} .payment) #contains the name before the .payment extension
			if [[ -f "${rewardsAcct}.hwsfile" && "${rewardsName}" == "${stakingName}" ]]; then
				cardanoHwCliParameters+="--reward-address-signing-key ${rewardsAcct}.hwsfile --reward-address-signing-key ${stakeAcct}.hwsfile"
		                echo -e "\e[0mRewards will be paid out to the same HW-Wallet Account: \e[32m${rewardsAcct}\e[90m.hwsfile\e[0m"
			else
				echo -e "\n\e[35mERROR - Registering a HW-StakingKey must also have a RewardsPaymentAccount on the same HW-Wallet.\e[0m";
				exit 1;
			fi

	                echo -e "\e[0mwhich is address: \e[32m${rewardsPayoutAddr}\e[0m"
			echo
	                echo -e "\e[0mHW-Wallet-StakeKey (Voting-Power) that will be used: \e[32m${stakeAcct}\e[90m.hwsfile\e[0m"
			echo
			echo -e "\e[0mNonce (current slotHeight): \e[32m${currentTip}\e[0m"
			echo

			start_HwWallet "" "5.0.1" ""; checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi
			tmp=$(${cardanohwcli} catalyst voting-key-registration-metadata --vote-public-key <(echo ${votePubKey}) ${cardanoHwCliParameters} --stake-signing-key "${stakeAcct}.hwsfile" --metadata-cbor-out-file "${votingMetaFile}" 2> /dev/stdout)
			if [[ "${tmp^^}" =~ (ERROR|DISCONNECT) ]]; then echo -e "\e[35m${tmp}\e[0m\n"; exit 1; else echo -e "\e[32mDONE\e[0m\n"; fi
			checkError "$?"; if [ $? -ne 0 ]; then exit $?; fi

			echo
	                if [ -f "${votingMetaFile}" ]; then #all good
				echo -e "\e[0mThe Metadata-Registration-CBOR File \"\e[32m${votingMetaFile}\e[0m\" was generated. :-)\n\nYou can now submit it on the chain by including it in a transaction with Script: 01_sendLovelaces.sh\nExample:\e[33m 01_sendLovelaces.sh mywallet mywallet min ${votingMetaFile}\n\n\e[0m"
						       else
				echo -e "\e[35mError - Something went wrong while writing the \"${votingMetaFile}\" metadata file !\e[0m\n"; exit 1;
			fi


		else #Voting for CLI StakeKey via cardano-signer

	                echo -e "\e[0mRewards will be paid out to PaymentAccount: \e[32m${rewardsAcct}\e[0m"
	                echo -e "\e[0mwhich is address: \e[32m${rewardsPayoutAddr}\e[0m"
			echo
	                echo -e "\e[0mStakeKey (Voting-Power) that will be used: \e[32m${stakeAcct}\e[90m.skey\e[0m"
			echo
			echo -e "\e[0mNonce (current slotHeight): \e[32m${currentTip}\e[0m"
			echo

			#Check the cardano-signer binary existance and version
			if ! exists "${cardanosigner}"; then
                                #Try the one in the scripts folder
                                if [[ -f "${scriptDir}/cardano-signer" ]]; then cardanosigner="${scriptDir}/cardano-signer";
                                else majorError "Path ERROR - Path to the 'cardano-signer' binary is not correct or 'cardano-singer' binaryfile is missing!\nYou can find it here: https://github.com/gitmachtl/cardano-signer/releases\nThis is needed to generate the signed Metadata. Also please check your 00_common.sh or common.inc settings."; exit 1; fi
			fi
			cardanosignerCheck=$(${cardanosigner} --version 2> /dev/null)
			if [[ $? -ne 0 ]]; then echo -e "\e[35mERROR - This script needs a working 'cardano-signer' binary. Please make sure you have it present with with the right path in '00_common.sh' !\e[0m\n\n"; exit 1; fi
			cardanosignerVersion=$(echo ${cardanosignerCheck} | cut -d' ' -f 2)
			versionCheck "${minCardanoSignerVersion}" "${cardanosignerVersion}"
			if [[ $? -ne 0 ]]; then majorError "Version ${cardanosignerVersion} ERROR - Please use a cardano-signer version ${minCardanoSignerVersion} or higher !\nOld versions are not compatible, please upgrade - thx."; exit 1; fi

			echo -e "\e[0mSigning with Cardano-Signer Version: \e[32m${cardanosignerVersion}\e[0m\n";
			showProcessAnimation "Signing " &
			tmp=$(${cardanosigner} sign --cip36 ${cardanoSignerParameters} --secret-key "${stakeAcct}.skey" --out-cbor "${votingMetaFile}" 2> /dev/stdout)
			if [ $? -ne 0 ]; then stopProcessAnimation; echo -e "\e[35m${tmp}\e[0m\n"; exit $?; fi
			stopProcessAnimation;

	                if [ -f "${votingMetaFile}" ]; then #all good
				echo -e "\e[0mThe Metadata-Registration-CBOR File \"\e[32m${votingMetaFile}\e[0m\" was generated. :-)\n\nYou can now submit it on the chain by including it in a transaction with Script: 01_sendLovelaces.sh\nExample:\e[33m 01_sendLovelaces.sh mywallet mywallet min ${votingMetaFile}\n\e[0m";
				if checkAdaRootHandleFormat "${rewardsAcct}"; then echo -e "\e[33mBe aware, the rewards address is now fixed. Moving the rootAdaHandle to another address will not change the rewards address!!!\e[0m\n"; fi
				if checkAdaSubHandleFormat "${rewardsAcct}"; then echo -e "\e[33mBe aware, the rewards address is now fixed. Moving the subAdaHandle to another address will not change the rewards address!!!\e[0m\n"; fi
				echo
						       else #hmm, something went wrong
				echo -e "\e[35mError - Something went wrong while generating the \"${votingMetaFile}\" metadata file !\e[0m\n"; exit 1;
			fi

		fi

                exit 0;
                ;;


  * ) 		showUsage; exit 1;
		;;
esac

