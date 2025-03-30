#!/bin/bash
ver=1.6

###################################################################################
# message functions for script

color() {
  YW=$(echo "\033[33m")
  BL=$(echo "\033[36m")
  RD=$(echo "\033[01;31m")
  BGN=$(echo "\033[4;92m")
  GN=$(echo "\033[1;92m")
  DGN=$(echo "\033[32m")
  CL=$(echo "\033[m")
  CM="${GN}✓${CL}"
  CROSS="${RD}✗${CL}"
  BFR="\\r\\033[K"
  HOLD=" "
}
export -f color

spinner() {
    local chars="/-\|"
    local spin_i=0
    if [[ -t 1 ]]; then printf "\e[?25l"; fi  # Hide cursor
    while true; do
      printf "\r \e[36m%s\e[0m" "${chars:spin_i++%${#chars}:1}"
      sleep 0.1
    done
}
export -f spinner

msg_info() {
    if [[ -n "$SPINNER_PID" ]] && ps -p "$SPINNER_PID" >/dev/null 2>&1; then
      kill "$SPINNER_PID" > /dev/null
      if [[ -t 1 ]]; then printf "\e[?25h"; fi # Show cursor
    fi
    local msg="$1"
    printf "%b" " ${HOLD} ${YW}${msg}   "
    if [[ -t 1 ]]; then
        spinner &
        SPINNER_PID=$!
    fi
}
export -f msg_info

msg_info_() {
    if [[ -n "$SPINNER_PID" ]] && ps -p "$SPINNER_PID" >/dev/null 2>&1; then
      kill "$SPINNER_PID" > /dev/null
      if [[ -t 1 ]]; then printf "\e[?25h"; fi # Show cursor
    fi
    local msg="$1"
    printf "%b" " ${HOLD} ${YW}${msg}   "
    if [[ -t 1 ]]; then
        spinner &
        SPINNER_PID=$!
    fi
}
export -f msg_info_

msg_ok() {
  if [[ -n "${SPINNER_PID// }" ]] && ps -p $SPINNER_PID >/dev/null 2>&1; then 
    kill $SPINNER_PID > /dev/null
    if [[ -t 1 ]]; then printf "\e[?25h"; fi # Show cursor
  fi
  local msg="$1"
  printf "%b" "${BFR} ${CM} ${GN}${msg}${CL}\n"
}
export -f msg_ok

msg_error() {
  if [[ -n "${SPINNER_PID// }" ]] && ps -p $SPINNER_PID >/dev/null 2>&1; then
    kill $SPINNER_PID > /dev/null
    if [[ -t 1 ]]; then printf "\e[?25h"; fi # Show cursor
  fi
  local msg="$1"
  printf "%b" "${BFR} ${CROSS} ${RD}${msg}${CL}\n"
}
export -f msg_error

###########################################################################################################################################################

export SPINNER_PID=""
set -Eeuo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
function error_handler() {
  # clear
  if [[ -n "$SPINNER_PID" ]] && ps -p $SPINNER_PID >/dev/null 2>&1; then kill $SPINNER_PID > /dev/null && printf "\e[?25h"; fi
  if [[ -t 1 ]]; then printf "\e[?25h"; fi # Show cursor
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  if mount | grep -q '/mnt/evernode-mount'; then
    guestunmount /mnt/evernode-mount/
  fi
  if mount | grep -q '/mnt/NPMplus-VM'; then
    guestunmount /mnt/NPMplus-VM/
  fi
  msg_error "an error occured, see above, cleared created temp directoy ($TEMP_DIR), and cleanly exiting..."
}

function cleanup() {
  if [[ -n "$SPINNER_PID" ]] && ps -p $SPINNER_PID >/dev/null 2>&1; then kill $SPINNER_PID > /dev/null && printf "\e[?25h"; fi
  if [[ -t 1 ]]; then printf "\e[?25h"; fi # Show cursor
  if mountpoint -q /mnt/evernode-mount; then guestunmount /mnt/evernode-mount; fi
  if mountpoint -q /mnt/NPMplus-VM; then guestunmount /mnt/NPMplus-VM; fi
  popd >/dev/null 2>&1 || true
  rm -rf $TEMP_DIR >/dev/null 2>&1 || true
}

function exit-script() {
  #clear
  echo -e "⚠  User exited script \n"
  exit
}

TEMP_DIR=$(mktemp -d)
gadget_encrypt="ipinfo.io/ip"
INTEGER='^[0-9]+([.][0-9]+)?$'
pushd $TEMP_DIR >/dev/null

###################################################################################
# used for testnet account setup/generation
function extract_json_add_to_file() {
  local file="${1:-$keypair_file}"
  local capture_json=false
  local json=""

  while IFS= read -r line; do
    if [[ $line == "Wallet:" ]]; then
      local capture_json=true
      continue
    fi

    if $capture_json; then
      local json+="$line"$'\n'
      # Check if the line contains a closing curly brace, indicating the end of the JSON block
      if [[ $line == *"}"* ]]; then
        break
      fi
    fi
  done

  # Ensure we only capture valid JSON by trimming leading/trailing whitespace, then save address/seed
  local json=$(echo "$json" | sed "s/'/\"/g" | sed 's/\([a-zA-Z0-9_]*\):/\1:/g')
  local address=$(echo "$json" | awk '/address:/ {print $2}' | tr -d '",')
  local seed=$(echo "$json" | awk '/secret:/ {print $2}' | tr -d '",')

  # Format output, and add a properly generated line to key_pair.txt
  if [ "$address" != "" ]; then 
    printf "Address: %s Seed: %s\n" $address $seed >> "$file"
    return 0
  fi
  return 1
}

####################################################################################
# installing of dependencies
function check_for_needed_program_installs() {
  local arg1="${1:-}"

  msg_info_ "checking and installing dependencies (jq, git, curl, unzip, libguestfs-tools, node, npm, npm-ws)..."
  cd /root/
  
  if [ -z "$arg1" ] && ! command -v guestmount &> /dev/null; then
    msg_info_ "installing libquestfs-tools...                                                                    "
    apt-get update >/dev/null 2>&1
    apt-get install -y libguestfs-tools 2>&1 | awk '{ printf "\r\033[K   installing libquestfs-tools.. "; printf "%s", $0; fflush() }'
    msg_ok "libquestfs-tools installed."
  fi
  
  if ! command -v jq &> /dev/null; then
    msg_info_ "installing jq...                                                                                  "
    apt-get update >/dev/null 2>&1
    apt-get install -y jq 2>&1 | awk '{ printf "\r\033[K   installing jq.. "; printf "%s", $0; fflush() }'
    msg_ok "jq installed."
  fi

  if ! command -v git &> /dev/null; then
    msg_info_ "installing git...                                                                                  "
    apt-get update >/dev/null 2>&1
    apt-get install -y git 2>&1 | awk '{ printf "\r\033[K   installing git.. "; printf "%s", $0; fflush() }'
    msg_ok "git installed."
  fi

  if ! command -v dialog &> /dev/null; then
    msg_info_ "installing dialog...                                                                                "
    apt-get update >/dev/null 2>&1
    apt-get install -y dialog 2>&1 | awk '{ printf "\r\033[K   installing dialog.. "; printf "%s", $0; fflush() }'
    msg_ok "dialog installed."
  fi

  if ! command -v bc &> /dev/null; then
    msg_info_ "installing bc...                                                                                    "
    apt-get update >/dev/null 2>&1
    apt-get install -y bc 2>&1 | awk '{ printf "\r\033[K   installing bc.. "; printf "%s", $0; fflush() }'
    msg_ok "bc installed."
  fi

  if ! command -v unzip &> /dev/null; then
    msg_info_ "installing unzip...                                                                                  "
    apt-get update >/dev/null 2>&1
    apt-get install -y unzip 2>&1 | awk '{ printf "\r\033[K   installing unzip.. "; printf "%s", $0; fflush() }'
    msg_ok "unzip installed."
  fi

  if ! command -v node &> /dev/null; then
    msg_info_ "installing nodejs...                                                                                  "
      apt-get update | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get install -y ca-certificates curl gnupg | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      mkdir -p /etc/apt/keyrings | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'

      NODE_MAJOR=20
      echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get update | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get -y install nodejs | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
    msg_ok "nodejs installed."
  else
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d. -f1)
    if [ "$NODE_VERSION" -lt 20 ]; then
      apt-get update | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get install -y ca-certificates curl gnupg | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      mkdir -p /etc/apt/keyrings | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'

      NODE_MAJOR=20
      echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get update | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get -y install nodejs | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      msg_ok "nodejs updated to newest."
    fi
  fi

  if ! command -v npm &> /dev/null; then
    msg_info_ "installing npm...                                                                                  "
      apt-get update | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get install -y ca-certificates curl gnupg | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      mkdir -p /etc/apt/keyrings | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'

      NODE_MAJOR=20
      echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get update | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get -y install nodejs npm | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
    msg_ok "npm installed, may need logging out and back in to take effect"
  fi

  if [ "$(node -e "try { require.resolve('ws'); console.log('true'); } catch (e) { console.log('false'); }")" = "false" ]; then
    msg_info_ "installing node websocket (ws)...                                                                                  "
    npm install -g ws  2>&1 | awk '{ printf "\r\033[K   installing node ws.. "; printf "%s", $0; fflush() }'
    npm install ws  2>&1 | awk '{ printf "\r\033[K   installing node ws.. "; printf "%s", $0; fflush() }'
    msg_ok "node ws installed."
  fi

  msg_ok "all dependencies checked, and installed."
}
export -f check_for_needed_program_installs

####################################################################################################################################################
###################################################################################
function wallet_management_script() {
  clear
  cd /root/
  msg_info_ "pre-checks..."
  check_for_needed_program_installs "no_guestmount_check"
  if [ -d "/root/evernode-deploy-monitor" ]; then
    echo "Pulling latest changes from github..."
    cd "/root/evernode-deploy-monitor"
    git pull || msg_error "unable to pull latest from git at present time?"
  else
    echo "Cloning https://github.com/gadget78/Evernode-Deploy-Monitor repository..."
    git clone https://github.com/gadget78/Evernode-Deploy-Monitor /root/evernode-deploy-monitor
    cd /root/evernode-deploy-monitor/
    cp .env.sample .env
    echo "updating NPM dependencies..."
    npm install -prefix /root/evernode-deploy-monitor
  fi
  cd "/root/evernode-deploy-monitor/"
  source .env

  if [ "$(node -e "try { require.resolve('evernode-js-client'); console.log('true'); } catch (e) { console.log('false'); }")" = "false" ]; then
    msg_info_ "installing node evernode-js-client...                                                                                  "
    npm install evernode-js-client  2>&1 | awk '{ printf "\r\033[K   installing node ws.. "; printf "%s", $0; fflush() }'
    msg_ok "node evernode-js-client installed."
  fi
  msg_ok "pre-checks complete."

  if [ -z "${monitor_ver:-}" ] || [ "${monitor_ver:-0}" -lt 4 ]; then
    if (whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --title ".env missmatch" --yesno ".env version missmatch, you may encounter errors,
do you want to auto update your .env file?
(current .env file will be backed up to .old.env)" 10 58); then
      cp .env .old.env
			if [ "$monitor_ver" == "1" ]; then
				sed -i '/^fee_adjust_amount/a\fee_max_amount=10000' .env
				sed -i '/^run_monitor_heartbeat/a\run_monitor_claimreward="true"' .env
				sed -i '/^keypair_file/a\keypair_rep_file="/root/key_pair_rep.txt"' .env  
				sed -i 's/^xahSourceAddress.*/sourceAccount="rSourceAddress"/' .env
				sed -i '/^xah_transfer/a\xah_transfer_reserve=10' .env
				sed -i 's/^push_url=.*/push_url="http:\/\/localhost:3001\/"/' .env     
				sed -i '/^evrSetupamount/a\evrSetupamount_rep=25' .env
				sed -i '/^xah_transfer_reserve/a\reputation_transfer="false"' .env
				sed -i 's/^monitor_ver=.*/monitor_ver=4/' .env
      elif [ "$monitor_ver" == "2" ]; then
				sed -i '/^evrSetupamount/a\evrSetupamount_rep=25' .env
				sed -i '/^xah_transfer_reserve/a\reputation_transfer="false"' .env
				sed -i 's/^monitor_ver=.*/monitor_ver=4/' .env
			elif [ "$monitor_ver" == "3" ]; then
				sed -i '/^xah_transfer_reserve/a\reputation_transfer="false"' .env
				sed -i 's/^monitor_ver=.*/monitor_ver=4/' .env
			else
				cp .env.sample .env
			fi
      source .env
    fi
  fi
  
  if [ "$use_testnet" == "true" ]; then DEPLOYMENT_NETWORK="testnet"; else DEPLOYMENT_NETWORK="mainnet"; fi

  if [ -s "$keypair_file" ]; then key_pair_count=$(grep -c '^Address' "$keypair_file"); else key_pair_count="0"; fi

  if [ -s "$keypair_rep_file" ]; then key_pair_rep_count=$(grep -c '^Address' "$keypair_rep_file"); else key_pair_rep_count="0"; fi

  # check key_pair file for accounts etc and report
  if ( [ "$use_keypair_file" == "true" ] && [ ! -f "$keypair_file" ] && [ "$DEPLOYMENT_NETWORK" == "testnet" ] ) || ( [ "$use_keypair_file" == "true" ] && [ "$DEPLOYMENT_NETWORK" == "testnet" ] && (( key_pair_count < 2 )) ); then 
    touch $keypair_file
    while true; do
      if NUM_VMS=$(whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --inputbox "the \"use_keypair_file\" is set to true,
with incorrect amount of key pairs in $keypair_file file
$key_pair_count key pairs found in file,

enter amount of testnet accounts to create. (minimum is 2) 
or 0 to skip (giving you access to manager)" 14 72 "3" --title "evernode count" 3>&1 1>&2 2>&3); then
        if ! [[ $NUM_VMS =~ $INTEGER ]]; then
          whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --msgbox "needs to be a number" 8 58
        elif [[ $NUM_VMS == 0 ]]; then
          break
        elif [ $NUM_VMS -gt 2 ]; then
          touch "$keypair_file"
          attempt=1
          if [  ! -f "$TEMP_DIR/test-account-generator.js" ]; then
            wget -q -O $TEMP_DIR/test-account-generator.js "https://gadget78.uk/test-account-generator.js" || msg_error "failed to download testnet account generator, restart script to try again"
          fi
          while true; do
            # Run the node testnet wallet generator, and capture address seed to key_pair.txt
            if [ -s "$keypair_file" ]; then key_pair_count=$(grep -c '^Address' "$keypair_file"); else key_pair_count="0"; fi
            if [[ $NUM_VMS -gt $key_pair_count ]]; then
              msg_info_ "generating keypairs, total so far $key_pair_count of $NUM_VMS (attempt $attempt, CTRL+C to exit !)         "
              node $TEMP_DIR/test-account-generator.js  2>/dev/null | extract_json_add_to_file 2>/dev/null || msg_info_ "timed out generating number $(( key_pair_count + 1 )), waiting a bit then trying again (we are on attempt $attempt)   ";  sleep 20; attempt=$((attempt + 1)); continue
              sleep 2
            else
              msg_ok "generated $NUM_VMS key pairs, and saved them in $keypair_file ready for the evernode installs/wallet management"
              break 2
            fi
          done
        fi
      else
        exit-script
      fi
    done

  # check key_pair_rep file for reputation accounts and report
  elif ( [ "$use_keypair_file" == "true" ] && [ ! -f "$keypair_rep_file" ] && [ "$DEPLOYMENT_NETWORK" == "testnet" ] ) || ( [ "$use_keypair_file" == "true" ] && [ "$DEPLOYMENT_NETWORK" == "testnet" ] && (( key_pair_rep_count < 1 )) ); then 
    touch $keypair_rep_file
    while true; do
      if NUM_VMS=$(whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --inputbox "the \"use_keypair_file\" is set to true,
with incorrect amount of key pairs in $keypair_rep_file file
$key_pair_rep_count key pairs found in file,

enter amount of testnet accounts to create. (minimum is 1) 
or 0 to skip (giving you access to manager)" 14 72 "3" --title "evernode count" 3>&1 1>&2 2>&3); then
        if ! [[ $NUM_VMS =~ $INTEGER ]]; then
          whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --msgbox "needs to be a number" 8 58
        elif [[ $NUM_VMS == 0 ]]; then
          break
        else
          touch "$keypair_file"
          attempt=1
          if [  ! -f "$TEMP_DIR/test-account-generator.js" ]; then
            wget -q -O $TEMP_DIR/test-account-generator.js "https://gadget78.uk/test-account-generator.js" || msg_error "failed to download testnet account generator, restart script to try again"
          fi
          while true; do
            # Run the node testnet wallet generator, and capture address seed to key_pair.txt
            if [ -s "$keypair_rep_file" ]; then key_pair_rep_count=$(grep -c '^Address' "$keypair_file"); else key_pair_rep_count="0"; fi
            if [[ $NUM_VMS -gt $key_pair_count ]]; then
              msg_info_ "generating keypairs, total so far $key_pair_count of $NUM_VMS (attempt $attempt, CTRL+C to exit !)         "
              node $TEMP_DIR/test-account-generator.js  2>/dev/null | extract_json_add_to_file $keypair_rep_file 2>/dev/null || msg_info_ "timed out generating number $(( key_pair_count )), waiting a bit then trying again (we are on attempt $attempt)   ";  sleep 20; attempt=$((attempt + 1)); continue
              sleep 2
            else
              msg_ok "generated $NUM_VMS key pairs, and saved them in $keypair_rep_file ready for the evernode installs/wallet management"
              break 2
            fi
          done
        fi
      else
        exit-script
      fi
    done

  elif ! [[ $(wc -l < "$keypair_file") -eq $key_pair_count ]]; then
      if dialog --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" \
                --defaultno --colors --title "problem detected" \
                --yesno "not every line in $keypair_file\nseems to start with \"Address:\"?\n\n\Zb\Z1this WILL cause issues, and needs to be fixed.\Zn\n\ncontinue to use Wallet Manager anyhows?" 12 58 ; then
        break
      else
        exit
      fi
  elif ! [[ $(wc -l < "$keypair_rep_file") -eq $key_pair_rep_count ]]; then
      if dialog --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" \
                --defaultno --colors --title "problem detected" \
                --yesno "not every line in $keypair_rep_file\nseems to start with \"Address:\"?\n\n\Zb\Z1this WILL cause issues, and needs to be fixed.\\Zn\n\ncontinue to use Wallet Manager anyhows?" 12 58 ; then
        break
      else
        exit
      fi
  elif [ "$use_keypair_file" == "true" ] && [ ! -f "$keypair_file" ]; then
    msg_error "no $keypair_file file, you need to create one for mainnet use,
one good method is using a vanity generator like this one https://github.com/nhartner/xrp-vanity-address"
    exit
  elif [ "$use_keypair_file" == "true" ] && [ $key_pair_count -lt 2 ]; then
    msg_error "use_keypair_file is set to true, but there is not enough account key pairs in $keypair_file file, minimum is 2 (source, and one for a evernode account)"
    exit
  elif [ "$use_keypair_file" == "true" ] && [ ! -f "$keypair_rep_file" ]; then
    msg_error "no $keypair_rep_file file, you need to create one for mainnet use,
one good method is using a vanity generator like this one https://github.com/nhartner/xrp-vanity-address"
    exit
  elif [ "$use_keypair_file" == "true" ] && [ $key_pair_rep_count -lt 1 ]; then
    msg_error "use_keypair_file is set to true, but there is not enough reputation account key pairs in $keypair_rep_file file, minimum is 2 (source, and one for a evernode account)"
    exit
  fi

  ####################################################################################################################################################
  #### START of main wallet management
  while true; do
    if WALLET_TASK=$(dialog --cancel-label "Exit" --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" \
       --title "Wallet Management" \
       --menu "Which module do you want to start?" 20 78 12 \
       "1" "Initiate a wallet_setup, used to prepare and setup key-pairs" \
       "2" "Initiate a EVR/XAH fund sweep" \
       "3" "Initiate a balance check and topup" \
       "4" "Initiate a heartbeat an reputation checkup" \
       "5" "Initiate claim Reward (aka BalanceAdjustment)" \
       "6" "Install the automated fund sweep, balance and heartbeat monitor" \
       "7" "Install or setup Uptime Kuma" \
       "8" "edit .env file (to change settings)" \
       "9" "edit key_pair.txt accounts file" \
       "0" "edit key_pair_rep.txt file for reputation accounts" \
       "h" "help area" \
       "<" "<<<< return back to main menu" \
       2>&1 >/dev/tty
    ); then

      ######### prep
      if [ "$WALLET_TASK" == "1" ]; then
        if [ ! -f "$keypair_file" ]; then
          msg_error "no $keypair_file file, you need a key_pair.txt file to use this module, maybe use vanity generator https://github.com/nhartner/xrp-vanity-address"
          break
        fi
        if [ "$use_testnet" == "true" ]; then
          xahaud_server=$xahaud_test
        else
          xahaud_server=$xahaud
        fi
        xahaud_server=$(echo "$xahaud_server" | sed -e 's/^wss:/https:/' -e 's/^ws:/http:/')
        source_account=$(sed "1q;d" "$keypair_file" | awk '{for (r=1; r<=NF; r++) if ($r == "Address:") print $(r+1)}')
        total_accounts=$(( (key_pair_count - 1) + key_pair_rep_count ))

        if curl -s -f "$xahaud_server" > /dev/null; then
          xahaud_server_working=$(curl -s -f -m 10 -X POST -H "Content-Type: application/json" -d '{"method":"server_info"}' "${xahaud_server}"  | jq -r '.result.status // "\\Z1failed\\Zn"' | xargs -I {} echo "\Z2{}\Zn")  || ( clear && whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --msgbox "error occured connecting to xahau server $xahaud_server" 8 58 && continue )
          xah_balance=$(curl -s -X POST -H "Content-Type: application/json" -d '{ "method": "account_info", "params": [ { "account": "'"$source_account"'", "strict": true, "ledger_index": "current", "queue": true } ] }' "${xahaud_server}" | jq -r '.result.account_data.Balance // "\\Z1not activated\\Zn"' )
          if [[ "$xah_balance" != *"not activated"* ]]; then
            xahSetupamount_calculated=$(( xahSetupamount * (key_pair_count - 1) ))
            xah_balance=$(echo "scale=1; $xah_balance / 1000000" | bc)
            if (( $(echo "$xahSetupamount_calculated > $xah_balance" | bc -l) )); then
              xahSetupamount_calculated="\Z1$xahSetupamount_calculated\Zn"
              xah_balance="\Z1$xah_balance\Zn"
            else
              xahSetupamount_calculated="\Z2$xahSetupamount_calculated\Zn"
              xah_balance="\Z2$xah_balance\Zn"
            fi
          else
            xahSetupamount_calculated="\Z1$(( xahSetupamount * ( key_pair_count - 1 ) ))\Zn"
          fi

          evr_balance=$(curl -s -X POST -H "Content-Type: application/json" -d '{ "method": "account_lines", "params": [ { "account": "'"$source_account"'", "ledger_index": "current" } ] }' "${xahaud_server}" | jq -r 'try .result.lines[] catch "failed" | try select(.currency == "EVR") catch "failed" | try .balance catch "\\Z1no trustline\\Zn"' )
          if [[ "$evr_balance" != *"no trustline"* ]]; then
            evrSetupamount_calculated=$(( ( evrSetupamount * ( key_pair_count -1 ) ) + ( evrSetupamount_rep * ( key_pair_rep_count ) ) ))
            if (( $(echo "$evrSetupamount_calculated > $evr_balance" | bc -l) )); then
              evrSetupamount_calculated="\Z1$evrSetupamount_calculated\Zn"
              evr_balance="\Z1$evr_balance\Zn"
            else
              evrSetupamount_calculated="\Z2$evrSetupamount_calculated\Zn"
              evr_balance="\Z2$evr_balance\Zn"
            fi
          else
            evrSetupamount_calculated="\Z1$(( evrSetupamount * ( key_pair_count - 1 ) ))\Zn"
          fi
        else
          xahaud_server_working="\Zb\Z1failed to connect\Zn"
          xah_balance="\Zb\Z1failed to connect\Zn"
          evr_balance="\Zb\Z1failed to connect\Zn"
        fi

        if dialog --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" \
       --title "Wallet Setup Module" --colors \
       --yesno "\
\Z0\ZbInfo on module:\Zn
    This module is used to prepare both key-pairs files
    \"$keypair_file\" and \"$keypair_rep_file\" files.
    It uses the first key-pair in \"$keypair_file\" for the source of XAH/EVR.
    Key pairs are prepared by:
    - Sending XAH to activate account,
    - Setting the EVR trustline, and sending EVR,
    - Setting regular key (using source account).
    It will then setup the .env so key_pair files are not needed for other operations.
    This will leave all accounts ready to be used for Evernode deployment.

\Z0\ZbSettings:\Zn
    use_testnet = \"$use_testnet\"
    xahau server = \"$xahaud_server\"
    XAH to send = \"$xahSetupamount\"
    EVR to evernode accounts = \"$evrSetupamount\"
    EVR to reputation accounts = \"$evrSetupamount_rep\"
    set_regular_key = \"$set_regular_key\"
    auto_adjust_fee = \"$auto_adjust_fee\"
    fee_adjust_amount = \"$fee_adjust_amount\"
    fee_max_amount = \"$fee_max_amount\"

\Z0\ZbCheckup:\Zn
    xahau server working = \"$xahaud_server_working\"
    evernode accounts to be parsed = \"$((key_pair_count -1))\"
    reputation accounts to be parsed = \"$key_pair_rep_count\"
    source account = \"$source_account\"
    total XAH needed = \"$xahSetupamount_calculated\" | amount in source account = \"$xah_balance\"
    total EVR needed = \"$evrSetupamount_calculated\" | amount in source account = \"$evr_balance\"

Do you want to use the above settings to setup all $total_accounts accounts?" 36 104; then
          clear
          node evernode_monitor.js wallet_setup && echo "sucessfull pass"
          echo ""
          read -n 1 -s -r -p "Press any key to continue..."
        fi

      ######### sweep
      elif [ "$WALLET_TASK" == "2" ]; then
        if [ "$use_testnet" == "true" ]; then
          xahaud_server=$xahaud_test
        else
          xahaud_server=$xahaud
        fi
        xahaud_server=$(echo "$xahaud_server" | sed -e 's/^wss:/https:/' -e 's/^ws:/http:/')
        if [ "$use_keypair_file" == "true" ]; then
          source_account=$(sed "1q;d" "$keypair_file" | awk '{for (r=1; r<=NF; r++) if ($r == "Address:") print $(r+1)}')
					account_count=$(( key_pair_count -1 ))
          if [ "$reputation_transfer" == "true" ]; then
						account_rep_count="$key_pair_rep_count"
						total_accounts=$(( account_count + key_pair_rep_count ))
					else
						account_rep_count="not enabled"
						total_accounts=$account_count
					fi
        else
          source_account="$sourceAccount"
          account_count=$(echo "$accounts" | wc -l)
					if [ "$reputation_transfer" == "true" ]; then
          	account_rep_count=$(echo "$reputationAccounts" | wc -l)
          	total_accounts=$(( $(echo "$accounts" | wc -l) + $(echo "$reputationAccounts" | wc -l) ))
					else
						account_rep_count="not enabled"
						total_accounts=$account_count
					fi
        fi
        if curl -s -f "$xahaud_server" > /dev/null; then
          xahaud_server_working=$(curl -s -f -m 10 -X POST -H "Content-Type: application/json" -d '{"method":"server_info"}' "${xahaud_server}"  | jq -r '.result.status // "\\Z1failed\\Zn"' | xargs -I {} echo "\Z2{}\Zn") || ( clear && whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --msgbox "error occured connecting to xahau server $xahaud_server" 8 58 && continue )
          xah_balance=$(curl -s -X POST -H "Content-Type: application/json" -d '{ "method": "account_info", "params": [ { "account": "'"$source_account"'", "strict": true, "ledger_index": "current", "queue": true } ] }' "${xahaud_server}" | jq -r '.result.account_data.Balance // "\\Z1not activated\\Zn"' )
          if [[ "$xah_balance" != *"not activated"* ]]; then
            xah_balance="\Z2$(echo "scale=1; $xah_balance / 1000000" | bc)\Zn"
          fi

          evr_balance=$(curl -s -X POST -H "Content-Type: application/json" -d '{ "method": "account_lines", "params": [ { "account": "'"$source_account"'", "ledger_index": "current" } ] }' "${xahaud_server}" | jq -r 'try .result.lines[] catch "failed" | try select(.currency == "EVR") catch "failed" | try .balance catch "\\Z1no trustline\\Zn"' )
          if [[ "$evr_balance" != *"no trustline"* ]]; then
            evr_balance="\Z2$evr_balance\Zn"
          fi
        else
          xahaud_server_working="\Zb\Z1failed to connect\Zn"
          xah_balance="\Zb\Z1failed to connect\Zn"
          evr_balance="\Zb\Z1failed to connect\Zn"
        fi
        if dialog --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" \
       --title "transfer_funds module" --colors \
       --yesno "\
\Z0\ZbInfo on module:\Zn
    This module is used to sweep EVR and XAH from all evernodes to the source account 
    it does this by utilising the regular key secret.
    so this needs to be set on all accounts (can be done with wallet setup module)

\Z0\ZbSettings:\Zn
    use_testnet = \"$use_testnet\"
    xahau server = \"$xahaud_server\"
    XAH transfer/sweep = \"$xah_transfer\"
    amount of XAH to leave in account = \"$xah_transfer_reserve\"
    minimum_EVR to trigger transfer = \"$minimum_evr_transfer\"
		reputation_transfer is enabled = \"$reputation_transfer\"
    auto_adjust_fee = \"$auto_adjust_fee\"
    fee_adjust_amount = \"$fee_adjust_amount\"

\Z0\ZbCheckup:\Zn
    xahau server working = \"$xahaud_server_working\"
    evernode accounts to be swept = \"$account_count\"
    reputation accounts to be swept = \"$account_rep_count\"
    source account/regular key = \"$source_account\"
    current XAH amount in source account = \"$xah_balance\"
    current EVR amount in source account = \"$evr_balance\"

Do you want to use the above settings to sweep \"$total_accounts\" accounts?" 32 104; then
          clear
          node evernode_monitor.js transfer_funds
          echo ""
          read -n 1 -s -r -p "Press any key to continue..."
        fi

      ######### check balance
      elif [ "$WALLET_TASK" == "3" ]; then
        if [ "$use_testnet" == "true" ]; then
          xahaud_server=$xahaud_test
        else
          xahaud_server=$xahaud
        fi
        xahaud_server=$(echo "$xahaud_server" | sed -e 's/^wss:/https:/' -e 's/^ws:/http:/')
        if [ "$use_keypair_file" == "true" ]; then
          source_account=$(sed "1q;d" "$keypair_file" | awk '{for (r=1; r<=NF; r++) if ($r == "Address:") print $(r+1)}')
					account_count="$((key_pair_count - 1))"
          account_rep_count="$key_pair_rep_count"
        	total_accounts=$(( (key_pair_count - 1) + key_pair_rep_count ))
        else
          source_account="$sourceAccount"
        	account_count=$(echo "$accounts" | wc -l)
          account_rep_count=$(echo "$reputationAccounts" | wc -l)
          total_accounts=$(( $(echo "$accounts" | wc -l) + $(echo "$reputationAccounts" | wc -l) ))
        fi
        if curl -s -f "$xahaud_server" > /dev/null; then
          xahaud_server_working=$(curl -s -f -m 10 -X POST -H "Content-Type: application/json" -d '{"method":"server_info"}' "${xahaud_server}"  | jq -r '.result.status // "\\Z1failed\\Zn"' | xargs -I {} echo "\Z2{}\Zn") || ( clear && whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --msgbox "error occured connecting to xahau server $xahaud_server" 8 58 && continue )
          xah_balance=$(curl -s -X POST -H "Content-Type: application/json" -d '{ "method": "account_info", "params": [ { "account": "'"$source_account"'", "strict": true, "ledger_index": "current", "queue": true } ] }' "${xahaud_server}" | jq -r '.result.account_data.Balance // "\\Z1not activated\\Zn"' )
          if [[ "$xah_balance" != *"not activated"* ]]; then
            xah_balance="\Z2$(echo "scale=1; $xah_balance / 1000000" | bc)\Zn"
          fi

          evr_balance=$(curl -s -X POST -H "Content-Type: application/json" -d '{ "method": "account_lines", "params": [ { "account": "'"$source_account"'", "ledger_index": "current" } ] }' "${xahaud_server}" | jq -r 'try .result.lines[] catch "failed" | try select(.currency == "EVR") catch "failed" | try .balance catch "\\Z1no trustline\\Zn"' )
          if [[ "$evr_balance" != *"no trustline"* ]]; then
            evr_balance="\Z2$evr_balance\Zn"
          fi
        else
          xahaud_server_working="\Zb\Z1failed to connect\Zn"
          xah_balance="\Zb\Z1failed to connect\Zn"
          evr_balance="\Zb\Z1failed to connect\Zn"
        fi

        if dialog --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" \
       --title "monitor_balance module" --colors \
       --yesno "\
\Z0\ZbInfo on module:\Zn
    This module iterates through all the accounts,
    and makes sure it has the correct amount of XAH and EVR 
    depending on settings, and account type.

\Z0\ZbSettings:\Zn
    use_testnet = \"$use_testnet\"
    xahau server = \"$xahaud_server\"
    xah_balance_threshold to trigger topup = \"$xah_balance_threshold\"
    amount of XAH to send = \"$xah_refill_amount\"
    evr_balance_threshold to trigger topup = \"$evr_balance_threshold\"
    amount of EVR to send = \"$evr_refill_amount\"
    auto_adjust_fee = \"$auto_adjust_fee\"
    fee_adjust_amount = \"$fee_adjust_amount\"

\Z0\ZbCheckup:\Zn
    xahau server working = \"$xahaud_server_working\"
    evernode accounts to check = \"$account_count\"
    reputation accounts to check = \"$account_rep_count\"
    source account = \"$source_account\"
    current XAH amount in source account = \"$xah_balance\"
    current EVR amount in source account = \"$evr_balance\"

Do you want to use the above settings to check \"$total_accounts\" account balances?" 32 104; then
          clear
          node evernode_monitor.js monitor_balance
          echo ""
          read -n 1 -s -r -p "Press any key to continue..."
        fi

      ######### check heartbeats
      elif [ "$WALLET_TASK" == "4" ]; then
        if [ "$use_testnet" == "true" ]; then
          xahaud_server=$xahaud_test
        else
          xahaud_server=$xahaud
        fi
        xahaud_server=$(echo "$xahaud_server" | sed -e 's/^wss:/https:/' -e 's/^ws:/http:/')
        if [ "$use_keypair_file" == "true" ]; then
          source_account=$(sed "1q;d" "$keypair_file" | awk '{for (r=1; r<=NF; r++) if ($r == "Address:") print $(r+1)}')
          total_accounts=$(( key_pair_count -1 ))
        else
          source_account="$sourceAccount"
          total_accounts=$(echo "$accounts" | wc -l)
        fi
        if curl -s -f "$xahaud_server" > /dev/null; then
          xahaud_server_working=$(curl -s -f -m 10 -X POST -H "Content-Type: application/json" -d '{"method":"server_info"}' "${xahaud_server}"  | jq -r '.result.status // "\\Z1failed\\Zn"' | xargs -I {} echo "\Z2{}\Zn") || ( clear && whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --msgbox "error occured connecting to xahau server $xahaud_server" 8 58 && continue )
          xah_balance=$(curl -s -X POST -H "Content-Type: application/json" -d '{ "method": "account_info", "params": [ { "account": "'"$source_account"'", "strict": true, "ledger_index": "current", "queue": true } ] }' "${xahaud_server}" | jq -r '.result.account_data.Balance // "\\Z1not activated\\Zn"' )
          if [[ "$xah_balance" != *"not activated"* ]]; then
            xah_balance="\Z2$(echo "scale=1; $xah_balance / 1000000" | bc)\Zn"
          fi

          evr_balance=$(curl -s -X POST -H "Content-Type: application/json" -d '{ "method": "account_lines", "params": [ { "account": "'"$source_account"'", "ledger_index": "current" } ] }' "${xahaud_server}" | jq -r 'try .result.lines[] catch "failed" | try select(.currency == "EVR") catch "failed" | try .balance catch "\\Z1no trustline\\Zn"' )
          if [[ "$evr_balance" != *"no trustline"* ]]; then
            evr_balance="\Z2$evr_balance\Zn"
          fi
        else
          xahaud_server_working="\Zb\Z1failed to connect\Zn"
          xah_balance="\Zb\Z1failed to connect\Zn"
          evr_balance="\Zb\Z1failed to connect\Zn"
        fi

        if [[ "$destinationEmail" != "" || "$destinationEmail" != "< your destination email >" ]]; then
          if [ "$email_notification" == "true" ]; then 
            email_used="\Z1NOT SET\Zn"
          else
            email_used="NOT SET"
          fi
        else
          if [ "$smtpEmail" == "<your account email in Brevo>" ]; then
            email_used="\Z1NOT SET\Zn"
          else
            email_used="$smtpEmail"
          fi
        fi
        if [ "$email_notification" == "true" ]; then email_notification_enabled="\Z2true\Zn"; else email_notification_enabled="\Z1false\Zn"; fi

        IFS=$'\n' read -r -d '' -a push_addresses_array <<< "$push_addresses" || true
        if [ "$push_notification" == "true" ]; then 
          push_notification_enabled="\Z2true\Zn"
          push_address_count=${#push_addresses_array[@]}
          if [ "$push_address_count" == "0" ]; then
            push_address_count="\Z10\Zn"
          fi
        else
          push_notification_enabled="\Z1false\Zn"
          push_address_count=${#push_addresses_array[@]}
        fi

        if dialog --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" \
       --title "monitor_heartbeats module" --colors \
       --yesno "\
\Z0\ZbInfo on module:\Zn
    This module iterates through all the accounts,
    and report back when the last heartbeat was of the evernode
    so you can check if the evernode has been working correctly. 

\Z0\ZbSettings:\Zn
    use_testnet = \"$use_testnet\"
    xahau server = \"$xahaud_server\"
    minutes_from_last_heartbeat_alert_threshold = \"$minutes_from_last_heartbeat_alert_threshold\"
    the interval (in minutes) between sending alert = \"$alert_repeat_interval_in_minutes\"

    email_notification enabled = \"$email_notification_enabled\"
    - email being used = \"$email_used\"

    UptimeKuma push_notification enabled = \"$push_notification_enabled\"
    - using UptimeKuma push_url = \"$push_url\"
    - number of addresses in push_addresses = \"$push_address_count\"

\Z0\ZbCheckup:\Zn
    xahau server working = \"$xahaud_server_working\"
    total evernodes to be checked = \"$total_accounts\"

Do you want to use the above settings to check heartbeats?" 30 104; then
          clear
          node evernode_monitor.js monitor_heartbeat
          echo ""
          read -n 1 -s -r -p "Press any key to continue..."
        fi

      ######### check claimrewards
      elif [ "$WALLET_TASK" == "5" ]; then
        if [ "$use_testnet" == "true" ]; then
          xahaud_server=$xahaud_test
        else
          xahaud_server=$xahaud
        fi
        xahaud_server=$(echo "$xahaud_server" | sed -e 's/^wss:/https:/' -e 's/^ws:/http:/')
        if [ "$use_keypair_file" == "true" ]; then
          source_account=$(sed "1q;d" "$keypair_file" | awk '{for (r=1; r<=NF; r++) if ($r == "Address:") print $(r+1)}')
					account_count=$(( key_pair_count - 1 ))
          account_rep_count=$key_pair_rep_count
        	total_accounts=$(( (key_pair_count - 1) + key_pair_rep_count ))
        else
          source_account="$sourceAccount"
          account_count=$(echo "$accounts" | wc -l)
          account_rep_count=$(echo "$reputationAccounts" | wc -l)
          total_accounts=$(( $(echo "$accounts" | wc -l) + $(echo "$reputationAccounts" | wc -l) ))
        fi
        if curl -s -f "$xahaud_server" > /dev/null; then
          xahaud_server_working=$(curl -s -f -m 10 -X POST -H "Content-Type: application/json" -d '{"method":"server_info"}' "${xahaud_server}"  | jq -r '.result.status // "\\Z1failed\\Zn"' | xargs -I {} echo "\Z2{}\Zn") || ( clear && whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --msgbox "error occured connecting to xahau server $xahaud_server" 8 58 && continue )
          xah_balance=$(curl -s -X POST -H "Content-Type: application/json" -d '{ "method": "account_info", "params": [ { "account": "'"$source_account"'", "strict": true, "ledger_index": "current", "queue": true } ] }' "${xahaud_server}" | jq -r '.result.account_data.Balance // "\\Z1not activated\\Zn"' )
          if [[ "$xah_balance" != *"not activated"* ]]; then
            xah_balance="\Z2$(echo "scale=1; $xah_balance / 1000000" | bc)\Zn"
          fi
        else
          xahaud_server_working="\Zb\Z1failed to connect\Zn"
          xah_balance="\Zb\Z1failed to connect\Zn"
        fi

        if dialog --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" \
       --title "monitor_claimrewards module" --colors \
       --yesno "\
\Z0\ZbInfo on module:\Zn
    This module iterates through ALL accounts (evernodes, and reputation accounts),
    will check if the account has been registered for balance adjustment rewards,
    if it has not, it will register.
    then will check and report if it can claim,
    and will tell you the amount claimable, date, and claim if possible.

\Z0\ZbSettings:\Zn
    use_testnet = \"$use_testnet\"
    xahau server = \"$xahaud_server\"

\Z0\ZbCheckup:\Zn
    xahau server working = \"$xahaud_server_working\"
    evernode accounts to check = \"$account_count\"
    reputation accounts to check = \"$account_rep_count\"

Do you want to use the above settings to check \"$total_accounts\" account registrations?" 28 104; then
          clear
          node evernode_monitor.js monitor_claimreward
          echo ""
          read -n 1 -s -r -p "Press any key to continue..."
        fi

      ######### install cronjob
      elif [ "$WALLET_TASK" == "6" ]; then
        if [ "$use_testnet" == "true" ]; then
          xahaud_server=$xahaud_test
        else
          xahaud_server=$xahaud
        fi
        xahaud_server=$(echo "$xahaud_server" | sed -e 's/^wss:/https:/' -e 's/^ws:/http:/')
        if [ "$use_keypair_file" == "true" ]; then
          source_account=$sourceAccount
          total_accounts=$(( (key_pair_count - 1) + key_pair_rep_count ))
        else
          source_account=$(sed "1q;d" "$keypair_file" | awk '{for (r=1; r<=NF; r++) if ($r == "Address:") print $(r+1)}')
          total_accounts=$(( $(echo "$accounts" | wc -l) + $(echo "$reputationAccounts" | wc -l) ))
        fi
        if curl -s -f "$xahaud_server" > /dev/null; then
          xahaud_server_working=$(curl -s -f -m 10 -X POST -H "Content-Type: application/json" -d '{"method":"server_info"}' "${xahaud_server}"  | jq -r '.result.status // "\\Z1failed\\Zn"' | xargs -I {} echo "\Z2{}\Zn") || ( clear && whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --msgbox "error occured connecting to xahau server $xahaud_server" 8 58 && continue )
          xah_balance=$(curl -s -X POST -H "Content-Type: application/json" -d '{ "method": "account_info", "params": [ { "account": "'"$source_account"'", "strict": true, "ledger_index": "current", "queue": true } ] }' "${xahaud_server}" | jq -r '.result.account_data.Balance // "\\Z1not activated\\Zn"' )
          if [[ "$xah_balance" != *"not activated"* ]]; then
            xah_balance="\Z2$(echo "scale=1; $xah_balance / 1000000" | bc)\Zn"
          fi
          evr_balance=$(curl -s -X POST -H "Content-Type: application/json" -d '{ "method": "account_lines", "params": [ { "account": "'"$source_account"'", "ledger_index": "current" } ] }' "${xahaud_server}" | jq -r 'try .result.lines[] catch "failed" | try select(.currency == "EVR") catch "failed" | try .balance catch "\\Z1no trustline\\Zn"' )
          if [[ "$evr_balance" != *"no trustline"* ]]; then
            evr_balance="\Z2$evr_balance\Zn"
          fi
        else
          xahaud_server_working="\Zb\Z1failed to connect\Zn"
          xah_balance="\Zb\Z1failed to connect\Zn"
          evr_balance="\Zb\Z1failed to connect\Zn"
        fi

        if dialog --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" \
       --title "install monitor as cronjob" --colors \
       --yesno "\
\Z0\ZbInfo on module:\Zn
    This module will install the evernode-deploy-monitor to run regularly depending on
    cronjob_main_hours setting in .env file, which is the amount of hours between triggers.
    it will also setup a seperate cronjob for the heartbeat module, which depends on
    cronjob_heartbeat_mins setting in .env file. which is the amount of minutes between triggers.
    you can manually run and test heartbeat module via main menu, option 4
    (setting cronjob times to zero, and running setting will disable/delete entry)

\Z0\ZbSettings:\Zn
    use_testnet = \"$use_testnet\"
    xahau server = \"$xahaud_server\"
    XAH transfer/sweep = \"$xah_transfer\"
    minimum_EVR to trigger transfer = \"$minimum_evr_transfer\"
    minutes_from_last_heartbeat_alert_threshold = \"$minutes_from_last_heartbeat_alert_threshold\"
    run_funds_transfer = \"$run_funds_transfer\"
    run_monitor_balance = \"$run_monitor_balance\"
    run_monitor_heartbeat = \"$run_monitor_heartbeat\"
    auto_adjust_fee = \"$auto_adjust_fee\"
    fee_adjust_amount = \"$fee_adjust_amount\"

\Z0\ZbCheckup:\Zn
    xahau server working = \"$xahaud_server_working\"
    total accounts to be monitored = \"$total_accounts\"
    source account = \"$source_account\"
    main cronjob to run every \"$cronjob_main_hours\" hours
    heartbeat module cronjob to run every \"$cronjob_heartbeat_mins\" minutes

Do you want to use the above settings to install monitor?" 32 104; then
          clear
          existing_crontab=$(crontab -l 2>/dev/null) || existing_crontab=""
          cronjob_main="* */$cronjob_main_hours * * * . $HOME/.bashrc && node /root/evernode-deploy-monitor/evernode_monitor.js"
          cronjob_heartbeat="*/$cronjob_heartbeat_mins * * * * . $HOME/.bashrc && node /root/evernode-deploy-monitor/evernode_monitor.js monitor_heartbeat"
          if crontab -l | grep -q "node /root/evernode-deploy-monitor/evernode_monitor.js"; then
              existing_crontab=$(echo "$existing_crontab" | sed 'node \/root\/evernode-deploy-monitor\/evernode_monitor\.js/d')
              existing_crontab=$(echo "$existing_crontab" | sed 'node \/root\/evernode-deploy-monitor\/evernode_monitor\.js/d')
              if [ "$cronjob_main_hours" != "0" ]; then existing_crontab="${existing_crontab}"$'\n'"${cronjob_main}" ;fi
              if [ "$cronjob_heartbeat_mins" != "0" ]; then existing_crontab="${existing_crontab}"$'\n'"${cronjob_heartbeat}" ;fi
              echo -e "${DGN}Cron job updated to run evernode monitor every $cronjob_main_hours hour(s), and heartbeat module every $cronjob_heartbeat_mins minutes${CL}"
          else
              if [ "$cronjob_main_hours" != "0" ]; then existing_crontab="${existing_crontab}"$'\n'"${cronjob_main}" ;fi
              if [ "$cronjob_heartbeat_mins" != "0" ]; then existing_crontab="${existing_crontab}"$'\n'"${cronjob_heartbeat}" ;fi
              echo -e "${DGN}Cron job added to run evernode monitor every $cronjob_main_hours hours, and heartbeat module every $cronjob_heartbeat_mins minutes${CL}"
          fi
          echo "$existing_crontab" | crontab -
          echo ""
          read -n 1 -s -r -p "Press any key to continue..."
        fi
      ######### uptime kuma
      elif [ "$WALLET_TASK" == "7" ]; then
        while true; do
          if UPTIMEKUMA_TASK=$(dialog --cancel-label "Exit" --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" \
            --title "uptime kuma" \
            --menu "What operation to perform?" 15 78 6 \
            "1" "install uptime kuma" \
            "2" "auto populate monitors with addresses in key_pair.txt file" \
            "3" "start the console viewer for uptime kuma" \
            "4" "details to setup NPM" \
            "<" "<<<< return back to menu" \
            2>&1 >/dev/tty
          ); then
            ######### install uptime kuma
            if [ "$UPTIMEKUMA_TASK" == "1" ]; then
              clear
              msg_info_ "git clone uptime-kuma repo...                                                                       "
              if [ -d "/root/uptime-kuma" ]; then
                  # echo "Pulling latest changes from github..."
                  cd /root/uptime-kuma
                  #git pull https://github.com/louislam/uptime-kuma.git master 2>&1 | awk '{ gsub(/[\r\n\t\v\f\b\033\/\-\|\\]/, ""); printf "\033[K\r     \033[33mgit updating repo.. \033[0m%s", substr($0, 1, 65) }' || msg_error "error pulling updates" || true
              else
                  #echo "Cloning https://github.com/louislam/uptime-kuma.git repository..."
                  git clone https://github.com/louislam/uptime-kuma.git /root/uptime-kuma 2>&1 | awk '{ gsub(/[\r\n\t\v\f\b\033\/\-\|\\]/, ""); printf "\033[K\r     \033[33mcloning repo.. \033[0m%s", substr($0, 1, 65) }' || msg_error "cloning repo" || true
                  cd /root/uptime-kuma
                  npm run setup  2>&1 | awk '{ gsub(/[\r\n\t\v\f\b\033\/\-\|\\]/, ""); printf "\033[K\r     \033[33msetting up.. \033[0m%s", substr($0, 1, 65) }' || msg_error "error running uptime kuma setup" || true
                  #echo "updating NPM dependencies..."
              fi
              msg_ok "uptime-kumo repo cloned."
              

              msg_info_ "installing pm2...                                                                                    "
              apt-get update >/dev/null 2>&1
              npm install pm2 -g 2>&1 | awk '{ gsub(/[\r\n\t\v\f\b\033\/\-\|\\]/, ""); printf "\033[K\r     \033[33minstalling pm2.. \033[0m%s", substr($0, 1, 75) }' || msg_error "installing pm2" || true
              pm2 install pm2-logrotate -g 2>&1| awk '{ gsub(/[\r\n\t\v\f\b\033\/\-\|\\]/, ""); printf "\033[K\r     \033[33minstalling pm2-logrotate.. \033[0m%s", substr($0, 1, 75) }' || true
              msg_ok "pm2 installed."

              msg_info_ "setting up pm2... and starting uptime-kuma                                                           "
              pm2 start /root/uptime-kuma/server/server.js --name uptime-kuma 2>&1 | awk '{ gsub(/[\r\n\t\v\f\b\033\/\-\|\\]/, ""); printf "\033[K\r     \033[33mstarting server.. \033[0m%s", substr($0, 1, 75) }' || msg_error "error starting uptime kuma (already running?)" || true 
              pm2 save 2>&1 | awk '{ gsub(/[\r\n\t\v\f\b\033\/\-\|\\]/, ""); printf "\033[K\r     \033[33minstalling at startup.. \033[0m%s", substr($0, 1, 75) }' || msg_error "error while saving setup" || true
              pm2 startup 2>&1 | awk '{ gsub(/[\r\n\t\v\f\b\033\/\-\|\\]/, ""); printf "\033[K\r     \033[33minstalling at startup.. \033[0m%s", substr($0, 1, 75) }' || msg_error "error while setting startup" || true
              msg_ok "uptime-kuma installed, and started"

              msg_info_ "checking firewall                                                                            "
              if command -v ufw &> /dev/null; then
                ufw allow 3001 2>&1 | awk '{ gsub(/[\r\n\t\v\f\b\033\/\-\|\\]/, ""); printf "\033[K\r     \033[33mchecking firewall.. \033[0m%s", substr($0, 1, 75) }'
                msg_ok "firewall checked and setup"
              else
                msg_ok "firewall app ufw not installed."
              fi
              echo
              LOCAL_IP=$(hostname -I | awk '{print $1}')
              echo -e "${CM}${DGN} uptime-kuma installed, and started, you can now configure a admin login, at ${BGN}http://${LOCAL_IP}:3001${CL}"
							echo -e "${DGN} then enter the user and pass, in the .env under push_user and push_pass, before you auto populate monitors.${CL}"

              echo
              read -n 1 -s -r -p "finished, Press any key to continue..."

            ######### auto populate uptime kuma monitors
            elif [ "$UPTIMEKUMA_TASK" == "2" ]; then
              clear
              if [ -z "$push_url" ] || [ -z "$push_user" ] || [ -z "$push_pass" ]; then
                echo ".env file not setup will all needed settings, check push_url, push_user, and push_pass entries and retry"
              elif [ ! -f "$keypair_file" ] || [ "$(( key_pair_count - 1 ))" -eq 0 ]; then
                echo "Not enough addresses to create files in $keypair_file."
              elif ! curl -s -f "$push_url" > /dev/null; then
                echo "unable to communicate with $push_url, this needs to be set properly as a fully working URL to your UptimeKuma page"
              else
                if [ ! -f kuma_cli ]; then 
                  wget -q -O /root/uptime-kuma/kuma_cli https://gadget78.uk/kuma_cli || msg_error "failed to download kuma command line (kuma_cli), restart script to try again"
                  chmod +x /root/uptime-kuma/kuma_cli
                fi
                push_addresses=""
                if [[ "$push_url" != */ ]]; then push_url="$push_url/"; fi

                kuma_monitor_list=$(/root/uptime-kuma/kuma_cli --url $push_url --username $push_user --password $push_pass monitor list)
                echo "Amount of monitors found already on your uptime kuma = $(echo "$kuma_monitor_list" | jq 'length')"

                for (( id=3; id<=$(( key_pair_count )); id++ ))
                do
                  # Extract the token_id (first 16 characters of the line)
                  token_id=$(grep '^Address' "$keypair_file" | sed -n "${id}p" | cut -c 10-26)
                  kuma_monitor_list_id=$(echo "$kuma_monitor_list" | jq -r 'to_entries[] | select(.value.pushToken == "'"$token_id"'") | .key')
                  #echo "$id, $token_id, $kuma_monitor_list"
                  if [ "$kuma_monitor_list_id" == "" ]; then
                    echo "adding monitor \"evernode $((id - 2))\" with token \"$token_id\"\n"
                    json_content=$(cat <<EOF
{
  "name": "evernode$((id - 2))",
  "type": "push",
  "active": "true",
  "interval": "1800",
  "retryInterval": "1800",
  "maxretries": "48",
  "push_token": "$token_id"
}
EOF
                    )
                    echo "$json_content" > "$TEMP_DIR/push_monitor_$id.json"
                    /root/uptime-kuma/kuma_cli --url $push_url --username $push_user --password $push_pass monitor add "$TEMP_DIR/push_monitor_$id.json"
                  else
                    echo "monitor already exists with token \"$token_id\" editing name to \"evernode $((id - 2))\""
                    json_content=$(cat <<EOF
{
  "id": "$kuma_monitor_list_id",
  "name": "evernode$((id - 2))",
  "type": "push",
  "active": "true",
  "interval": "1800",
  "retryInterval": "1800",
  "maxretries": "48",
  "push_token": "$token_id"
}
EOF
                    )
                    echo "$json_content" > "$TEMP_DIR/push_monitor_$id.json"
                    /root/uptime-kuma/kuma_cli --url $push_url --username $push_user --password $push_pass monitor edit "$TEMP_DIR/push_monitor_$id.json"
                  fi

                  push_addresses="${push_addresses}${push_url}api/push/${token_id}"$'\n'
                  sleep 2
                done
                echo
                push_addresses=$(printf '%s\n' "$push_addresses" | sed '$!N;s/\n$//')                 # removed the now uneeded last "added newline"
                push_addresses=$(echo "$push_addresses" | sed ':a;N;$!ba;s/[&/\]/\\&/g;s/\n/\\n/g')   # checks and adds breakout characters for special characters including newline characters etc
                sed -i -e "/^push_addresses=/,/^[[:space:]]*$/ {
                  /^push_addresses=/!d
                  s|^push_addresses=.*|push_addresses=\"${push_addresses}\"\\n|
                }" /root/evernode-deploy-monitor/.env
              fi
              echo
              read -n 1 -s -r -p "finished, Press any key to continue..."

            ######### pm2 monit
            elif [ "$UPTIMEKUMA_TASK" == "3" ]; then
              clear
              pm2 monit || msg_error "problem with running or finding pm2 monitor"
              echo
              read -n 1 -s -r -p "finished, Press any key to continue..."
            
            ######### NPM info
            elif [ "$UPTIMEKUMA_TASK" == "4" ]; then
              clear
              LOCAL_IP=$(hostname -I | awk '{print $1}')
              echo "use NPM, and setup a new proxy host, using preferred Domain, with IP of http://${LOCAL_IP} and port 3001"
              read -n 1 -s -r -p "finished, Press any key to continue..."
            
            ######### return to main menu
            elif [ "$UPTIMEKUMA_TASK" == "<" ]; then
              break
            fi

          else
            exit-script
          fi
        done

      ######### config .env
      elif [ "$WALLET_TASK" == "8" ]; then
        nano /root/evernode-deploy-monitor/.env
        source /root/evernode-deploy-monitor/.env
      ######### key_pair.txt edit
      elif [ "$WALLET_TASK" == "9" ]; then
        nano $keypair_file
        if [ -s "$keypair_file" ]; then key_pair_count=$(grep -c '^Address' "$keypair_file"); else key_pair_count="0"; fi
      ######### key_pair_rep.txt edit
      elif [ "$WALLET_TASK" == "0" ]; then
        nano $keypair_rep_file
        if [ -s "$keypair_rep_file" ]; then key_pair_rep_count=$(grep -c '^Address' "$keypair_file"); else key_pair_rep_count="0"; fi
      ######### help area
      elif [ "$WALLET_TASK" == "h" ]; then
        while true; do
          if HELP_PAGES=$(dialog --cancel-label "Exit" --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" \
            --title "help pages" \
            --menu "Which help page to you want to view?" 15 78 6 \
            "1" "main wallet managerment help file" \
            "2" "help with key_pair.txt files" \
            "3" "help setting up uptime kuma" \
            "4" "FAQ" \
            "<" "<<<< return back to menu" \
            2>&1 >/dev/tty
          ); then
          
          if [ "$HELP_PAGES" == "1" ]; then
            dialog --backtitle "README Viewer" --title "README.md" --textbox "README.md" 40 90
          elif [ "$HELP_PAGES" == "<" ]; then
            break
          fi

          fi
        done
      ######### return
      elif [ "$WALLET_TASK" == "<" ]; then
        start_
      fi
    ######### exit
    else
      exit-script
    fi
  done
}

####################################################################################################################################################
###################################################################################
function install_npmplus() {
  clear
  cat <<"EOF"
 _ _  ___  __ __       _
| \ || . \|  \  \ ___ | | _ _  ___
|   ||  _/|     || . \| || | |[_-[
|_\_||_|  |_|_|_||  _/|_| \__|/__/
                 |_|
-------------------------------------

EOF
  echo -e "Loading..."
  source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)
  APP="NginxProxyManagerPlus"
  SPINNER_PID=""
  check_for_needed_program_installs

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "${APP}" --yesno "Do you want to Install, or Update NPMplus?" 10 58 --yes-button "Update" --no-button "Install" --defaultno); then
    export install_npmplus="false"
    export install_version="latest"
    cluster_resources=$(pvesh get /cluster/resources --output-format=json)
    while true; do
      if UPDATE_ID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter your NPMplus CT or VM ID" 8 58 "100" --title "VM/CT ID" 3>&1 1>&2 2>&3); then
        if ! [[ $UPDATE_ID =~ $INTEGER ]]; then
          whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "⚠ ID MUST BE AN INTEGER NUMBER" 8 58
        elif ! jq -r '.[].vmid' <<< "$cluster_resources" | grep -q "^$UPDATE_ID$"; then
          whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "ID ${UPDATE_ID}, doesnt exist" 8 58
        elif [[ $(jq -r ".[] | select(.vmid == $UPDATE_ID) | .status" <<< "$cluster_resources") != "running" ]]; then
          whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "ID ${UPDATE_ID}, needs to be running" 8 58
        elif [[ $(jq -r ".[] | select(.vmid == $UPDATE_ID) | .type" <<< "$cluster_resources") != "lxc" ]] && ! qm guest cmd $UPDATE_ID ping > /dev/null 2>&1; then
          whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "ID ${UPDATE_ID}, is a VM, but doesnt have a running guest agent" 8 58
        else
          break
        fi
      else
        exit-script
      fi
    done
    if [[ $(jq -r ".[] | select(.vmid == $UPDATE_ID) | .type" <<< "$cluster_resources") == "lxc" ]]; then
      lxc-attach -n "$UPDATE_ID" -- bash -c "$(wget -qLO - https://gadget78.uk/npmplus-install.sh)" && msg_ok "NPM plus sucessfully updated" || { msg_error "fault setting up container"; exit; }
    else
      msg_info_ "${DGN}VM detected and running, connecting to issue update commands...${CL}"
      # Execute the command on the guest VM and capture the JSON response
      UPDATE_response=$(qm guest exec $UPDATE_ID --timeout 180 -- bash -c "$(wget -qLO - https://gadget78.uk/npmplus-install.sh)" 2>&1)

      # Parse JSON response to check if command succeeded
      UPDATE_error=$( { echo "$UPDATE_response" | jq -r '.["exitcode"]' || { echo "UPDATE_error capture failed"; true; }; } )
      UPDATE_output=$( { echo "$UPDATE_response" | jq -r '.["out-data"]' || { echo "UPDATE_ouput capture failed"; true; }; } )

      if [[ "$UPDATE_error" == "0" ]]; then
          msg_ok "VM $UPDATE_ID: Updated succeeded." && echo -e "${DGN}Output:${CL}" && echo "$UPDATE_output"
      else
          msg_error "VM $UPDATE_ID: Update failed. Error message: full response=$UPDATE_response -- error=$UPDATE_error -- output=$UPDATE_output"
      fi

    fi
    return
  fi
  
  export var_disk="4"
  export var_cpu="2"
  export var_ram="4096"
  export var_os="debian"
  export var_version="12"

  export NEXTID=$(pvesh get /cluster/nextid)
  export DISK_SIZE="$var_disk"
  export CORE_COUNT="$var_cpu"
  export RAM_SIZE="$var_ram"
  export PW=""
  export HN="$APP"
  export BRG="vmbr0"
  export NET="dhcp"
  export GATE=""
  export APT_CACHER=""
  export APT_CACHER_IP=""
  export DISABLEIP6="no"
  export SD=""
  export NS=""
  export MAC=""
  export VLAN=""
  export MTU=""
  export SSH="no"
  export VERB="no"
  export STD=""
  export install_npmplus="true"
  export install_version="latest"
  export install_portainer="false"
  variables
  catch_errors
  color

  ### Install as CT
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "${APP}" --yesno "Do you want to install this into a CT or VM?" 10 58  --yes-button "CT" --no-button "VM" ); then
    export install_type="CT"
    export CT_ID=$NEXTID
    export CT_TYPE="1"
    
    echo -e "${DGN}NPM+ version to install: ${BGN}$install_version${CL}"
    echo -e "${DGN}Install Portainer?: ${BGN}$install_portainer${CL}"
    echo_default

  while true; do
    if NET=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "${APP}" --inputbox "Set IPv4 Address" 8 58 $NET --title "IP ADDRESS" 3>&1 1>&2 2>&3); then
      if [ -z "$NET" ]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "${APP}" --msgbox "IP address cannot be empty" 8 58
      elif [ "$NET" == "dhcp" ]; then
        echo -e "${DGN}Using IP Address: ${BGN}$NET${CL} (over-rides above)"
        break
      elif [[ ! "$NET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "${APP}" --msgbox "$NET is an invalid IPv4 address. Please enter a valid IPv4 address" 8 58
      else
        if ! ping -c 1 -W 1 "$NET" &>/dev/null; then
          echo -e "${DGN}Using IP Address: ${BGN}$NET${CL}"
          NET="${NET}/24"
          BASE_IP="$NET"
          while true; do
            if GATE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "${APP}" --inputbox "Set gateway IPv4 Address" 8 58 "192.168.0.1" --title "IP ADDRESS" 3>&1 1>&2 2>&3); then
              if [ -z "$GATE1" ]; then
                whiptail --backtitle "Proxmox VE Helper Scripts" --title "${APP}" --msgbox "IP address cannot be empty" 8 58
              elif [[ ! "$GATE1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                whiptail --backtitle "Proxmox VE Helper Scripts" --title "${APP}" --msgbox "$GATE1 is an invalid IPv4 address. Please enter a valid IPv4 address" 8 58
              else
                GATE=",gw=$GATE1"
                echo -e "${DGN}Using Gateway IP Address: ${BGN}$GATE1${CL} (over-rides above)"
                break
              fi
            fi
          done
            if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --inputbox "Set Bridge" 8 58 "vmbr0" --title "BRIDGE" 3>&1 1>&2 2>&3); then
              if [ -z "$BRG" ]; then
                BRG="vmbr0"
                echo -e "${DGN}Using Bridge default: ${BGN}$BRG${CL}"
                break 2
              else
                echo -e "${DGN}Using Bridge: ${BGN}$BRG${CL}"
                break 2
              fi
            else
              exit-script
            fi
        else
          whiptail --backtitle "Proxmox VE Helper Scripts" --title "${APP}" --msgbox "IP Clash detected with IP(s)
$NET" 8 64
        fi
      fi
    else
      exit-script
    fi
  done

    while true; do
      printf "Change above default settings? (y/n): "
      read -r change_settings
      change_settings="${change_settings:-n}"  # Default to 'n' if empty
      case "$change_settings" in
        [yY]|[yY][eE][sS]) 
          change_settings="y"
          break
          ;;
        [nN]|[nN][oO]) 
          change_settings="n"
          break
          ;;
        *)
          echo "Please enter 'y' or 'n'."
          ;;
      esac
    done

    if [[ "$change_settings" == "y" ]]; then
      advanced_settings

      if (whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "Portainer" --yesno "Install portainer?" 10 58); then
        export install_portainer="true"
      else
        export install_portainer="false"
      fi
      echo -e "${DGN}Install Portainer?: ${BGN}$install_portainer${CL}"

      while true; do
        if install_version=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "what version of NPMplus do you want to install?" 8 58 "$install_version" --title "NPM+ version" 3>&1 1>&2 2>&3); then
          if [[ "$install_version" =~ ^[0-9]+$ ]] && (( install_version >= 340 && install_version <= 800 )); then
            echo -e "${DGN}NPM+ version to install: ${BGN}$install_version${CL}"
            break
          elif [[ "$install_version" == "latest" ]]; then
            echo -e "${DGN}NPM+ version to install: ${BGN}$install_version${CL}"
            break
          else
            whiptail --backtitle "Proxmox VE Helper Scripts" --msgbox "verrsion needs to be latest, or a number between 340 and 800" 8 64
            install_version="latest"
          fi
        else
          exit-script
        fi
      done
    fi
    
    build_container

    lxc-attach -n "$CTID" -- bash -c "$(wget -qLO - https://gadget78.uk/npmplus-install.sh)" || { msg_error "fault setting up container"; exit; }

    IP=$(pct exec "$CTID" ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
    pct set "$CTID" -description "<div align='center'><a href='https://github.com/ZoeyVid/NPMplus'><img src='https://github.com/ZoeyVid/NPMplus/blob/2024-07-11-r1/frontend/app-images/logo-text-vertical-grey.png?raw=true' /></a>
<a href='https://$IP:81' target='_blank'>https://${IP}:81</a>

<a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'><img src='https://raw.githubusercontent.com/tteck/Proxmox/main/misc/images/logo-81x112.png'/></a></div>"

    exit

  ### Install as VM 
  else
    export install_version="latest"
    export NEXTID=$(pvesh get /cluster/nextid)
    export VMID=$NEXTID
    export MACHINE=""
    export DISK_CACHE=""
    export FORMAT=",efitype=4m"
    export SWAP_KBYTES="4194304"
    export CPU_TYPE=" -cpu host"
    export THIN="discard=on,ssd=1,"
    export SSH_ROOT="$SSH"
    export SSH_KEY=""
    export TEMPLATE_STORAGE="local"
    export cloud_init_LOCATION="/var/lib/vz/snippets/"
    export UBUNTU_URL="https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
    export NPMPLUS_INSTALL_URL="https://gadget78.uk/npmplus-install.sh"

    BASE_IMAGE_FILE=$(basename $UBUNTU_URL)
    if [  ! -f /tmp/$BASE_IMAGE_FILE ]; then
      msg_info_ "no Ubuntu base image found, downloading ${CL}${BL}${UBUNTU_URL}${CL}"
      wget -q --show-progress -O /tmp/$BASE_IMAGE_FILE $UBUNTU_URL  && msg_ok "Downloaded ${CL}${BL}${BASE_IMG_FILE}${CL}" || { msg_error "failed to download Ubuntu image file, check URL/name?,restart script to try again"; exit; }
    else
      msg_ok "Ubuntu base found, using $BASE_IMAGE_FILE"
    fi

    #generate cloud-init .yaml file
    mkdir -p $cloud_init_LOCATION
    rm -f $cloud_init_LOCATION/NPMplus_VM.yml
    cat > $cloud_init_LOCATION/NPMplus_VM.yml <<EOF
#cloud-config
disable_root: false
ssh_authorized_keys:
  - $SSH_KEY
write_files:
  - path: /etc/systemd/system/getty@.service.d/autologin.conf
    permissions: '0644'
    content: |
      [Service]
      ExecStart=
      ExecStart=-/sbin/agetty --autologin root --keep-baud %I 115200,38400,9600 \$TERM
  - path: /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf
    permissions: '0644'
    content: |
      [Service]
      ExecStart=
      ExecStart=-/sbin/agetty --autologin root --keep-baud %I 115200,38400,9600 \$TERM
  - path: /etc/profile
    content: |
      res() {

      old=\$(stty -g)
      stty raw -echo min 0 time 5

      printf '\0337\033[r\033[999;999H\033[6n\0338' > /dev/tty
      IFS='[;R' read -r _ rows cols _ < /dev/tty

      stty "\$old"

      # echo "cols:\$cols"
      # echo "rows:\$rows"
      stty cols "\$cols" rows "\$rows"
      }

      [ \$(tty) = /dev/ttyS0 ] && res
swap:
  filename: /.swapfile
  size: ${SWAP_KBYTES}K
growpart:
  mode: auto
  devices: ['/']
  ignore_growroot_disabled: false
runcmd:
  - echo -e "${YW}1/6 starting cloud-init commands, 1st is apt updat/upgrade, and getting qamu-guest-agent up to watch install...${CL}"
  - [ "/bin/systemctl", "daemon-reload" ]
  - timedatectl set-timezone $timezone
  - apt-get update || true
  - apt-get upgrade -y || true
  - apt-get install -y jq unzip qemu-guest-agent
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - export timezone="$timezone"
  - export install_version="$install_version"
  - export install_npmplus="$install_npmplus"
  - /root/npmplus-install.sh | tee /root/npmplus-install.log
EOF

    msg_info_ "(re)cloning base img..."
    IMAGE_FILE="/tmp/cloned/$BASE_IMAGE_FILE"
    rm -f -r /tmp/cloned/
    mkdir /tmp/cloned/
    cp /tmp/$BASE_IMAGE_FILE $IMAGE_FILE
    msg_ok "img file cloned"
    
    msg_info_ "mounting and copying installer into place..."
    mkdir -p /mnt/NPMplus-VM
    guestmount -a $IMAGE_FILE -m /dev/sda1 /mnt/NPMplus-VM

    wget -q -O /mnt/NPMplus-VM/root/npmplus-install.sh $NPMPLUS_INSTALL_URL || { msg_error "failed to download npmplus-install setup script for VM, restart script to try again"; exit; }
    chmod +x /mnt/NPMplus-VM/root/npmplus-install.sh

    guestunmount /mnt/NPMplus-VM
    msg_ok "files now on img, now ready to create VM"

    while read -r line; do
      TAG=$(echo $line | awk '{print $1}')
      TYPE=$(echo $line | awk '{printf "%-10s", $2}')
      FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
      ITEM="  Type: $TYPE Free: $FREE "
      OFFSET=2
      if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
          MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
      fi
      STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
    done < <(pvesm status -content images | awk 'NR>1')
    VALID=$(pvesm status -content images | awk 'NR>1')
    if [ -z "$VALID" ]; then
      msg_error "Unable to detect a valid storage location."
      exit
    else
      while [ -z "${VM_STORAGE:+x}" ]; do
        VM_STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --title "Evernode Storage Pools" --radiolist \
        "Which storage pool you would like to use?\nTo make a selection, use the Spacebar.\n" \
        16 $(($MSG_MAX_LENGTH + 23)) 6 \
        "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3) || exit
      done
    fi
    STORAGE="$VM_STORAGE"
    echo -e "${DGN}Using ${BGN}$STORAGE${CL}${DGN} for Storage Location.${CL}"

    STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
    case $STORAGE_TYPE in
    nfs | dir)
    DISK_EXT=".qcow2"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format qcow2"
    THIN=""
    ;;
    btrfs)
    DISK_EXT=".raw"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format raw"
    THIN=""
    ;;
    esac
    for i in {0,1}; do
    disk="DISK$i"
    eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
    eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
    done

    if [[ -z "$MAC" ]]; then MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//'); fi

    msg_info_ "Creating a VM, with ID $VMID "
    qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $((RAM_SIZE)) \
    -name "$HN" -tags proxmox-helper-scripts -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
    pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null || { msg_error "failed to create a VM$VMID Disk, this normally happens when this disk already exists, check the $STORAGE pool"; exit; }
    qm importdisk $VMID ${IMAGE_FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
    qm set $VMID \
    -efidisk0 ${DISK0_REF}${FORMAT} \
    -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN} \
    -scsi1 ${STORAGE}:cloudinit \
    -boot order=scsi0 \
    -serial0 socket \
    -ciuser root \
    -ipconfig0 ip="$NET$GATE" \
    -cicustom "user=${TEMPLATE_STORAGE}:snippets/NPMplus_VM.yml" \
    -description "<div align='center'><a href='https://github.com/ZoeyVid/NPMplus'><img src='https://github.com/ZoeyVid/NPMplus/blob/2024-07-11-r1/frontend/app-images/logo-text-vertical-grey.png?raw=true' /></a>

<a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'><img src='https://raw.githubusercontent.com/tteck/Proxmox/main/misc/images/logo-81x112.png'/></a></div>" 1>&/dev/null

    qm resize $VMID scsi0 +"${DISK_SIZE}G" 1>&/dev/null
    msg_ok "Finished Creating VM, ID $VMID, named ${CL}${BL}(${HN})"

    msg_info_ "Starting.."
    qm start $VMID >/dev/null || msg_error "failed to start VM"
    msg_ok "Succesfully created and Started VM, ID $VMID, $HN"
    echo -e "${DGN}you can check how the install went, or is going from ${BGN}WITHIN${CL}${DGN} the VM(not here),"
    echo -e "using log file, /root/npmplus-install.log"
    echo -e "for example,"
    echo -e "cat /root/npmplus-install.log"
    echo -e "or"
    echo -e "tail -f /root/npmplus-install.log${CL}"
  fi

}

####################################################################################################################################################
###################################################################################

function npmplus_setup() {
  while true; do
    if NPM_URL=$(whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --inputbox "Whats your NPMplus dashboard URL?(normally ends in :81)" 8 64 ${NPM_URL:-https://192.168.0.1:81} --title "NPM URL" 3>&1 1>&2 2>&3); then
      if ! curl -k -s -f "${NPM_URL}/api/" > /dev/null; then
        whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "⚠ this URL doesnt seem to resolve properly" 8 78
      else
        if NPM_TOKEN=$(whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --inputbox "Whats your NPM API Token?(leave blank if you dont have one)" 8 64 ${NPM_TOKEN:-} --title "NPM API Token" 3>&1 1>&2 2>&3); then
          if [ "$NPM_TOKEN" == "" ]; then
            if NPM_USER=$(whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --inputbox "Whats your NPM login email?(so we can generate a API Token)" 8 64 "your@email.com" --title "NPM USER" 3>&1 1>&2 2>&3); then
              if [ "$NPM_USER" == "" ]; then
                whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "⚠ NPM email has to be set" 8 58
              elif [[ ${#NPM_USER} -gt 40 ]]; then
                whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "⚠ NPM email length should not exceed 40 characters." 8 58
              elif [[ ! $NPM_USER =~ .+@.+ ]]; then
                whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "⚠ NPM email address is invalid." 8 58
              else
                if NPM_PASS=$(whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --inputbox "Whats your NPM login password?(so we can generate a API Token)" 8 68 "yourpassword" --title "NPM PASS" 3>&1 1>&2 2>&3); then
                  if [ "$NPM_PASS" == "" ]; then
                    whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "⚠ password has to be set" 8 58
                  elif [ ${#NPM_PASS} -lt 8 ]; then
                    whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "⚠ password is too short, needs to be over 8 characters" 8 64
                  else
                    if curl -k -s -f "${NPM_URL}/api/" > /dev/null; then
                      NPM_TOKEN=$(curl -k -s -m 10 "$NPM_URL/api/tokens" -H "Content-Type: application/json; charset=UTF-8" --data-raw "{\"identity\":\"$NPM_USER\",\"secret\":\"$NPM_PASS\",\"expiry\":\"50y\"}" | jq -r '.token // "failed"' 2>/dev/null || echo "failed" )
                    else 
                      NPM_TOKEN="failed"
                    fi
                    if [ "$NPM_TOKEN" != "failed" ]; then
                      echo -e "${DGN}NPM URL set to: ${BGN}$NPM_URL${CL}"
                      echo -e "${DGN}NPM token test result: ${BGN}CREATED${CL}${DGN}, save the below API token for future use.${CL}"
                      echo "$NPM_TOKEN"
                      read -n 1 -s -r -p "Press any key to continue..."
                      break
                    else
                      whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "⚠ Token creation did not work \nresponded with $NPM_TOKEN" 10 64
                    fi
                  fi
                fi
              fi
            fi
          else
            if curl -k -s -f "$NPM_URL/api/" > /dev/null; then
              NPM_CHECK_RESPONSE=$(curl -k -s -m 10 -X GET -H "Content-Type: application/json; charset=UTF-8" -H "Authorization: Bearer $NPM_TOKEN" $NPM_URL/api/users/me | jq -r '.email // "no email entry"' 2>/dev/null || echo "no json output" )
            else 
              NPM_CHECK_RESPONSE="no response from URL"
            fi
            if [[ $NPM_CHECK_RESPONSE =~ .+@.+ ]]; then
              echo -e "${DGN}NPM URL set to: ${BGN}$NPM_URL${CL}"
              echo -e "${DGN}NPM token test result: ${BGN}PASSED${CL}${DGN}, API token linked to email $NPM_CHECK_RESPONSE${CL}"
              break
            else
              whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "⚠ Token did not work, response was:
$NPM_CHECK_RESPONSE" 8 64
            fi
          fi
        fi
      fi
    else
      exit
    fi
  done
}


function dns_server_installer() {

  if ! dpkg -s apt-utils &> /dev/null; then
    msg_info_ "installing apt-utils...                                                                                  "
      apt-get update >/dev/null 2>&1
      apt-get install -y apt-utils 2>&1 | awk '{ printf "\r\033[K   installing apt-utils.. "; printf "%s", $0; fflush() }'
    msg_ok "apt-utils installed."
  fi

  if ! command -v lsof &> /dev/null; then
    msg_info_ "installing lsof...                                                                                  "
      apt-get update >/dev/null 2>&1
      apt-get install -y lsof 2>&1 | awk '{ printf "\r\033[K   installing lsof.. "; printf "%s", $0; fflush() }'
    msg_ok "lsof installed."
  fi

  if ! command -v node &> /dev/null; then
    msg_info_ "installing nodejs...                                                                                  "
      apt-get update | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get install -y ca-certificates curl gnupg | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      mkdir -p /etc/apt/keyrings | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'

      NODE_MAJOR=20
      echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get update | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get -y install nodejs | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
    msg_ok "nodejs installed."
  else
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d. -f1)
    if [ "$NODE_VERSION" -lt 20 ]; then
      apt-get update | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get install -y ca-certificates curl gnupg | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      mkdir -p /etc/apt/keyrings | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'

      NODE_MAJOR=20
      echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get update | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get -y install nodejs | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      msg_ok "nodejs updated to newest."
    fi
  fi

  if ! command -v npm &> /dev/null; then
    msg_info_ "installing npm...                                                                                  "
      apt-get update | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get install -y ca-certificates curl gnupg | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      mkdir -p /etc/apt/keyrings | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'

      NODE_MAJOR=20
      echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get update | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
      apt-get -y install nodejs | awk '{ printf "\r\033[K   installing node.. "; printf "%s", $0; fflush() }'
    msg_ok "npm installed, may need loging out and back in to take effect"
  fi

  if [ "$DNS_ID_TYPE" == "qemu" ]; then
    msg_info_ "checking port 53"
    if lsof -i :53 > /dev/null 2>&1; then
      echo "Port 53 is in use. checking to see if its systemd-resolved"
      PROCESS_INFO=$(lsof -i :53 -Fpcn | awk -F: '/^p/{pid=$2} /^c/{command=$2} /^n/{name=$2; print pid, command, name}')
      if echo "$PROCESS_INFO" | grep -q "systemd-resolved"; then
        sudo systemctl stop systemd-resolved
        # Verify if systemd-resolved was stopped successfully
        if [ $? -eq 0 ]; then
            echo "systemd-resolved stopped successfully."

            # Check if port 53 is now free
            if ! lsof -i :53 > /dev/null 2>&1; then
                msg_ok "Port 53 is now free. adding fallback nameserver to /etc/resolv.conf"
                # Add missing DNS servers
                DNS_SERVERS=("1.1.1.1" "8.8.8.8")
                for DNS in "${DNS_SERVERS[@]}"; do
                  if ! grep -q "^nameserver $DNS$" /etc/resolv.conf; then
                    echo "nameserver $DNS" >> /etc/resolv.conf
                  fi
                done
            else
                msg_error "stopping systemd-resolved Failed to free port 53. Another process may still be using it. process list: $PROCESS_INFO"
            fi
        else
            msg_error "Failed to stop systemd-resolved. Check permissions or if the service exists. process list: $PROCESS_INFO"
        fi
      else
        msg_error "port 53 is not being used by systemd-resolved, unable to resolve issue, process is $PROCESS_INFO"
      fi
    else
      msg_ok "Port 53 is free. No action needed."
    fi
  else
    msg_info_ "checking port 53"
    if lsof -i :53 > /dev/null 2>&1; then
      msg_ok "Port 53 is in use. but we are in CT so its ok..."
    fi
    msg_ok "port 53 is not in use"
  fi

  npm install -g npm@latest
  npm install -g express express-rate-limit node-dns dns2 node-forge pm2
  pm2 install pm2-logrotate
  sudo wget -q -O /root/dns-api.js https://gadget78.uk/dns-api.js
  export PM2_HOME="/root/.pm2"
  export NODE_PATH=$(npm root -g)

cat <<EOF > /root/ecosystem.config.js
module.exports = {
  apps: [
    {
      name: 'dnsapi',
      script: '/root/dns-api.js',
      cwd: '/root',
      env: {
        PM2_HOME: '$PM2_HOME',
        NODE_PATH: '$NODE_PATH',
      },
    },
  ],
};
EOF

  PM2_HOME="$PM2_HOME" pm2 start /root/ecosystem.config.js
  PM2_HOME="$PM2_HOME" pm2 startup systemd -u root
  PM2_HOME="$PM2_HOME" pm2 save

  echo 
  read -n 1 -s -r -p "Press any key to continue (next step is to setup API proxy entry)..."
}


function install_dnsserver() {
  clear
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "DNS server system" --yesno "Do you want to (re)Install the evernode DNS server system?" 10 64 --yes-button "(re)install" --no-button "exit" ); then
    if ! [ "${DNS_ID_TYPE:-}" = "lxc" ] || [ "${DNS_ID_TYPE:-}" == "quemu" ]; then
      cluster_resources=$(pvesh get /cluster/resources --output-format=json)
      while true; do
        if DNS_ID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Enter your NPMplus CT/VM ID" 8 58 "100" --title "CT/VM ID" 3>&1 1>&2 2>&3); then
          if ! [[ $DNS_ID =~ $INTEGER ]]; then
            whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "⚠ ID MUST BE AN INTEGER NUMBER" 8 58
          elif ! jq -r '.[].vmid' <<< "$cluster_resources" | grep -q "^$DNS_ID$"; then
            whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "ID ${DNS_ID}, doesnt exist" 8 58
          elif [[ $(jq -r ".[] | select(.vmid == $DNS_ID) | .status" <<< "$cluster_resources") != "running" ]]; then
            whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "CT ID ${DNS_ID}, needs to be running" 8 58
          elif [[ $(jq -r ".[] | select(.vmid == $DNS_ID) | .type" <<< "$cluster_resources") != "lxc" ]] && ! qm guest cmd $DNS_ID ping > /dev/null 2>&1; then
            whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "ID ${DNS_ID}, is a VM, but doesnt have a running guest agent" 8 58
          else
            break
          fi
        else
          exit-script
        fi
      done
      DNS_ID_TYPE=$(jq -r ".[] | select(.vmid == $DNS_ID) | .type" <<< "$cluster_resources") && msg_ok "will now install the DNS system into VMID, $DNS_ID, which is a $DNS_ID_TYPE container" || msg_error "unable to identify cotainer type of ID $DNS_ID"
    fi

    if [[ "$DNS_ID_TYPE" == "lxc" ]]; then
      lxc-attach -n "$DNS_ID" -- bash -c "$(declare -f msg_info_); $(declare -f msg_error); $(declare -f msg_ok); $(declare -f dns_server_installer); export DNS_ID_TYPE=$DNS_ID_TYPE; dns_server_installer" && msg_ok "DNS server and API successfully (re)installed" || { msg_error "fault setting up container"; exit; }
      dns_server_ip=$(lxc-info -n $DNS_ID -iH | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -vE '^172\.17\.')
    else
      msg_info_ "${DGN}VM detected and running, connecting and (re)installing DNS system...${CL}"
      # Execute the command on the guest VM and capture the JSON response
      UPDATE_response=$(qm guest exec $DNS_ID --timeout 180 -- bash -c "$(declare -f msg_info_); $(declare -f msg_error); $(declare -f msg_ok); export DNS_ID_TYPE=$DNS_ID_TYPE; export PM2_HOME=\"/root/.pm2\"; export NODE_PATH=\"/usr/lib/node_modules\"; $(declare -f dns_server_installer); dns_server_installer" 2>&1)

      # Parse JSON response to check if command succeeded
      UPDATE_error=$( { echo "$UPDATE_response" | jq -r '.["exitcode"]' || { echo "UPDATE_error capture failed"; true; }; } )
      UPDATE_output=$( { echo "$UPDATE_response" | jq -r '.["out-data"]' || { echo "UPDATE_ouput capture failed"; true; }; } )

      if [[ "$UPDATE_error" == "0" ]]; then
          msg_ok "VM $DNS_ID: Updated succeeded." && echo -e "${DGN}Output:${CL}" && echo "$UPDATE_output"
      else
          msg_error "VM $DNS_ID: Update had a failure. Error message: full response=$UPDATE_response -- error=$UPDATE_error -- output=$UPDATE_output" 
      fi
      dns_server_ip=$(qm guest exec $DNS_ID -- bash -c "hostname -I | cut -d' ' -f1" | jq -r '.["out-data"]' | xargs)
    fi

    if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "DNS server system" --yesno "add/update the proxyhost forwarder to NPMplus?" 10 64 --yes-button "Add/Update" --no-button "exit" ); then
      touch /root/.deployenv
      source /root/.deployenv
      BASE_DOMAIN="${BASE_DOMAIN:-yourdomain.com}"
      while true; do
        if BASE_DOMAIN=$(whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --inputbox "Set the base domain of your evernodes (part after the subdomain)" 8 68 "$BASE_DOMAIN" --title "domain" 3>&1 1>&2 2>&3); then
          if [ -z "$BASE_DOMAIN" ]; then
              whiptail --backtitle "Proxmox VE Helper Scripts" --msgbox "base domain needs to be set" 8 58
          else
              echo -e "${DGN}Using base domain: ${BGN}$BASE_DOMAIN${CL}"
              break
          fi
        else
          exit-script
        fi
      done
      dns_server_api="dnsapi.${BASE_DOMAIN}"

      npmplus_setup

      # Get/Set NPM_CERT_ID (TLS file)
      NPM_CERT_ID_WILD="false"
      NPM_CERT_LIST=$(curl -k -s -m 100 -X GET -H "Content-Type: application/json; charset=UTF-8" -H "Authorization: Bearer $NPM_TOKEN" $NPM_URL/api/nginx/certificates || echo "" )
      NPM_CERT_ID=$(echo "$NPM_CERT_LIST" | jq -r '[.[] | select(.nice_name? == "'"$dns_server_api"'") | .id // empty] | if length == 0 then "" else .[] end' || echo "" )
      if [ -z "$NPM_CERT_ID" ]; then # check for wildcard domain too
          NPM_CERT_ID=$(echo "$NPM_CERT_LIST" | jq -r '[.[] | select(.nice_name? == "*.'"${dns_server_api#*.}"'") | .id // empty] | if length == 0 then "" else .[] end' || echo "" )
          if [ -n "$NPM_CERT_ID" ]; then echo -e "${DGN}Using a wildcard SSL${CL}"; NPM_CERT_ID_WILD="true"; fi
      fi
      if [[ -z "$NPM_CERT_ID" || "$NPM_CERT_ID" == "null" ]]; then # SSL not found, needs setting up...
        if [[ -z "$CERT_EMAIL" ]]; then CERT_EMAIL="your@email.com"; fi
        while true; do
          if CERT_EMAIL=$(whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --inputbox "Set your SSL certificate email " 8 58 "$CERT_EMAIL" --title "certificate email" 3>&1 1>&2 2>&3); then
            if [[ ${#CERT_EMAIL} -gt 40 ]]; then
              whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "Email address length should not exceed 40 characters." 8 58
            elif [[ ! $CERT_EMAIL =~ .+@.+ ]]; then
              whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "Email address is invalid." 8 58
            else
              echo -e "${DGN}Using email address for certificate : ${BGN}$CERT_EMAIL${CL}"
              break
            fi
          else
            exit-script
          fi
        done
        NPM_CERT_ADD=$(curl -k -s -m 100 -X POST -H "Content-Type: application/json; charset=UTF-8" -H "Authorization: Bearer $NPM_TOKEN" -d '{"provider":"letsencrypt","nice_name":"'"$dns_server_api"'","domain_names":["'"$dns_server_api"'"],"meta":{"letsencrypt_email":"'"$NPM_CERT_EMAIL"'","letsencrypt_agree":true,"dns_challenge":false}}' $NPM_URL/api/nginx/certificates ) || echo "failed to create certificate for DNS server API, this WILL cause issues. ERROR; debug: $NPM_CERT_ADD"
        NPM_CERT_ID=$(jq -r '.id' <<< "$NPM_CERT_ADD") && echo -e "${DGN}created new certificate for host domain $dns_server_api, ID is $NPM_CERT_ID${CL}" || msg_error "failed to find certificate ID, this WILL cause issues. ERROR; debug1: $NPM_CERT_ADD debug2: $NPM_CERT_ID"
      else
        echo -e "${DGN}Using existing certificate for host domain $dns_server_api, with ID:$NPM_CERT_ID   WILDCARD:$NPM_CERT_ID_WILD${CL}"
      fi
      # Setup proxy Host
      NPM_PROXYHOSTS_LIST=$( { curl -k -s -m 100 -X GET -H "Content-Type: application/json; charset=UTF-8" -H "Authorization: Bearer $NPM_TOKEN" $NPM_URL/api/nginx/proxy-hosts || { msg_error "something went wrong getting NPM list of proxy hosts"; NPM_PROXYHOSTS_LIST={}; }; } )
      NPM_PROXYHOSTS_ID=$( { echo "$NPM_PROXYHOSTS_LIST" | jq -r '.[] | select(.domain_names[] == "'"$dns_server_api"'") | .id' || echo ""; } )
      if [ "$NPM_PROXYHOSTS_ID" == "" ]; then
          echo -e "${DGN}adding new proxy host domain $dns_server_api using NPM_CERT_ID: $NPM_CERT_ID${CL}"
          NPM_ADD_RESPONSE=$( { curl -k -s -m 100 -X POST -H "Content-Type: application/json; charset=UTF-8" -H "Authorization: Bearer $NPM_TOKEN" -d '{"domain_names":["'"$dns_server_api"'"],"forward_host":"'"$dns_server_ip"'","forward_port":8443,"access_list_id":0,"certificate_id":'"$NPM_CERT_ID"',"ssl_forced":1,"caching_enabled":0,"block_exploits":1,"advanced_config":"","meta":{"letsencrypt_agree":true,"nginx_online":true},"allow_websocket_upgrade":1,"http2_support":0,"forward_scheme":"https","locations":[],"hsts_enabled":0,"hsts_subdomains":0}' $NPM_URL/api/nginx/proxy-hosts || { echo "something went wrong when adding $dns_server_api proxy host"; NPM_ADD_RESPONSE="error"; }; } ) 
          NPM_ADD_RESPONSE_CHECK=$(jq -r '.enabled // "no enabled entry"' <<< "$NPM_ADD_RESPONSE" || echo "jq error, no json output?")
          if [[ "$NPM_ADD_RESPONSE_CHECK" == "1" || "$NPM_ADD_RESPONSE_CHECK" == "true" ]]; then
              msg_ok "added new dns server API to NPM+ with domain $dns_server_api${CL}"
              NPM_PROXYHOSTS_ID=$( echo "$NPM_ADD_RESPONSE" | jq -r '.id')
          else
              msg_error "failed to add dns server API domain on NPM+ $dns_server_api, this will cause issues connecting via this domain. (debug_check:$NPM_ADD_RESPONSE_CHECK   debug_response:$NPM_ADD_RESPONSE )"
          fi
      else
          echo -e "${DGN}proxy host already on NPM domain $dns_server_api, updating (using a NPM_CERT_ID: $NPM_CERT_ID)..."
          NPM_EDIT_RESPONSE=$( { curl -k -s -m 100 -X PUT -H "Content-Type: application/json; charset=UTF-8" -H "Authorization: Bearer $NPM_TOKEN" -d '{"domain_names":["'"$dns_server_api"'"],"forward_host":"'"$dns_server_ip"'","forward_port":8443,"access_list_id":0,"certificate_id":'"$NPM_CERT_ID"',"ssl_forced":1,"caching_enabled":0,"block_exploits":1,"advanced_config":"","meta":{"letsencrypt_agree":true,"nginx_online":true},"allow_websocket_upgrade":1,"http2_support":0,"forward_scheme":"https","locations":[],"hsts_enabled":0,"hsts_subdomains":0}' $NPM_URL/api/nginx/proxy-hosts/$NPM_PROXYHOSTS_ID || { echo "something went wrong when updating $dns_server_api proxy host"; NPM_EDIT_RESPONSE="error"; }; })
          NPM_EDIT_RESPONSE_CHECK=$(jq -r '.enabled // "no enabled entry"' <<< "$NPM_EDIT_RESPONSE" || echo "jq error, no json output?")
          if [[ "$NPM_EDIT_RESPONSE_CHECK" == "1" || "$NPM_EDIT_RESPONSE_CHECK" == "true" ]]; then
              msg_ok "updated proxy host with domain $dns_server_api"
          else
              msg_error "failed to edit proxy host domain on NPM+, this will cause issues connecting via this domain. ( debug_check:$NPM_EDIT_RESPONSE_CHECK    debug_response:$NPM_EDIT_RESPONSE )"
          fi
      fi

    else
      whiptail --backtitle "Proxmox VE Helper Scripts: evernode deploy script $ver" --msgbox "you have chosen NOT to auto setup NPM+,
 you will have to manually add a forwarder, or a proxyhost in NPM+,
 using a domain of htps://dnsapi.yourbasedomain.com
 to IP $dns_server_ip, and port 8443
(also seperately, port forward port 53 for the DNS server)" 12 90
    fi

    return
  fi
}



###################################################################################
function xahau_script() {
    msg_info_ "starting xahau node script..."
    bash -c "$(wget -qLO - https://raw.githubusercontent.com/gadget78/xahl-node/main/setup.sh)"
    msg_ok "install/update complete."
    exit
}

###################################################################################
function evernode_deploy_script() {
  export ENTRY_STRING=$(curl -s $gadget_encrypt | base64 | tr '+/' '-_' | tr -d '=' ) || { ENTRY_STRING="string_fail" ; true; }
  DEPLOY_STATUS=$(curl -o /dev/null -s -w "%{http_code}\n" https://deploy.zerp.network/$ENTRY_STRING.sh) || { DEPLOY_STATUS="failed"; true; }
  if curl -s -f "https://deploy.zerp.network" > /dev/null; then
    if [ "$DEPLOY_STATUS" == "403" ]; then
      whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --msgbox "you do not have full access to the evernode deploy script,
contact @gadget78 to negotiate access.
giving him this code $ENTRY_STRING" 10 58
      exit
    elif [ "$DEPLOY_STATUS" == "404" ]; then
      whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --msgbox "deploy script not present ?
contact @gadget78 with your code $ENTRY_STRING
or just try again in 15 mins" 10 58
      exit
    elif [ "$DEPLOY_STATUS" == "failed" ]; then
      whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --msgbox "failed connecting to deploy server,
contact @gadget78 for help.
code tried = $ENTRY_STRING" 10 58
      exit
    else
      bash -c "$(wget -qLO - https://deploy.zerp.network/$ENTRY_STRING.sh)" || true
    fi
  else
    whiptail --backtitle "Proxmox VE Helper Scripts: Wallet Management. version $ver" --msgbox "unable to connect to deploy server?
contact @gadget78 for access.
giving him this code $ENTRY_STRING" 10 58
    exit
  fi
}

###################################################################################################################################################################################################################################
###################################################################################################################################################################################################################################
# It All Starts Here !

function start_() {
  if command -v pveversion >/dev/null 2>&1; then
    if MODULE=$(whiptail --backtitle "Proxmox VE Helper Scripts: Deploy Management. version $ver" \
                  --title "Proxmox detected..." \
                  --menu "Which module do you want to start?" 12 42 4 \
                  "1" "Wallet Management" \
                  "2" "Evernode Deployment" \
                  "3" "Install/Update NPMplus" \
                  "4" "(re)Install DNS server system" \
                  --ok-button "Select" \
                  --cancel-button "Exit" \
                  3>&1 1>&2 2>&3); then
      if [ "$MODULE" == "1" ]; then
        wallet_management_script 
      elif [ "$MODULE" == "2" ]; then
        evernode_deploy_script
      elif [ "$MODULE" == "3" ]; then
        install_npmplus
      elif [ "$MODULE" == "4" ]; then
        install_dnsserver
      fi
    else
      exit-script
    fi
  fi

  if ! command -v pveversion >/dev/null 2>&1; then
    if MODULE2=$(whiptail --backtitle "Proxmox VE Helper Scripts: Deploy Management. version $ver" \
                  --title "Proxmox NOT detected..." \
                  --menu "Which module do you want to start?" 12 48 5 \
                  "1" "Wallet Management" \
                  "2" "Xahau Server Install/Update" \
                  "3" "NPMplus Install/Update" \
                  "4" "(re)install DNS server system" \
                  "5" "setup NPM+ for a standalone(VPS) evernode" \
                  --ok-button "Select" \
                  --cancel-button "Exit" \
                  3>&1 1>&2 2>&3); then
      if [ "$MODULE2" == "1" ]; then
        wallet_management_script
      elif [ "$MODULE2" == "2" ]; then
        xahau_script
      elif [ "$MODULE2" == "3" ]; then
        bash -c "$(wget -qLO - https://gadget78.uk/npmplus-install.sh)" || { msg_error "fault setting up container"; exit; }
      elif [ "$MODULE2" == "4" ]; then
        if systemctl is-active --quiet qemu-guest-agent; then 
          export DNS_ID_TYPE="quemu"
        else
          export DNS_ID_TYPE="lxc"
        fi
        install_dnsserver
      elif [ "$MODULE2" == "5" ]; then
        npmplus_setup

        HOST_ADDRESS=$(jq -r '.hp.host_address' /etc/sashimono/sa.cfg)
        BASE_DOMAIN=${HOST_ADDRESS#*.}

        NPM_CERT_ID_WILD="false"
        NPM_CERT_LIST=$(curl -k -s -m 100 -X GET -H "Content-Type: application/json; charset=UTF-8" -H "Authorization: Bearer $NPM_TOKEN" $NPM_URL/api/nginx/certificates || echo "" )
        NPM_CERT_ID=$(echo "$NPM_CERT_LIST" | jq -r '[.[] | select(.nice_name? == "'"$HOST_ADDRESS"'") | .id // empty] | if length == 0 then "" else .[] end' || echo "" )
        if [ -z "$NPM_CERT_ID" ]; then # check for wildcard domain
            NPM_CERT_ID=$(echo "$NPM_CERT_LIST" | jq -r '[.[] | select(.nice_name? == "*.'"$BASE_DOMAIN"'") | .id // empty] | if length == 0 then "" else .[] end' || echo "" )
            if [ -n "$NPM_CERT_ID" ]; then echo -e "${DGN}Using a wildcard SSL${CL}"; NPM_CERT_ID_WILD="true"; fi
        fi
        jq '.proxy.tls_type = "NPMplus" |
          .proxy.npm_url = "'"$NPM_URL"'" |
          .proxy.wildcard = "'"$NPM_CERT_ID_WILD"'" |
          .proxy.npm_tokenPath = "/home/sashimbxrpl/.evernode-host/.host-account-secret.key" |
          .proxy.blacklist = [ "'"$BASE_DOMAIN"'" ]' \
          /etc/sashimono/mb-xrpl/mb-xrpl.cfg > /etc/sashimono/mb-xrpl/mb-xrpl.cfg.backup \
        && mv /etc/sashimono/mb-xrpl/mb-xrpl.cfg.backup /etc/sashimono/mb-xrpl/mb-xrpl.cfg \
        && jq '.npm.token = "'"$NPM_TOKEN"'"' $(jq -r '.proxy.npm_tokenPath' /etc/sashimono/mb-xrpl/mb-xrpl.cfg) > $(jq -r '.proxy.npm_tokenPath' /etc/sashimono/mb-xrpl/mb-xrpl.cfg).backup && mv $(jq -r '.proxy.npm_tokenPath' /etc/sashimono/mb-xrpl/mb-xrpl.cfg).backup $(jq -r '.proxy.npm_tokenPath' /etc/sashimono/mb-xrpl/mb-xrpl.cfg) \
        && msg_ok "/etc/sashimono/mb-xrpl/mb-xrpl.cfg file edited to set these proxy detils; NPM_URL to '"$NPM_URL"', wildcard set to $NPM_CERT_ID_WILD, blacklist domain(s) set to $BASE_DOMAIN, and entry to npm_tokenPath" \
        && msg_ok "$(jq -r '.proxy.npm_tokenPath' /etc/sashimono/mb-xrpl/mb-xrpl.cfg) file edited to add above NPMplus token" \
        || echo "FAILED to add or update NPM details"
      fi
    else
      echo "no input"
      exit-script
    fi
  fi
}
if ! command -v curl &> /dev/null; then
  echo "installing curl .... "
  apt-get update >/dev/null 2>&1 | awk '{ printf "\r\033[K   updating.. "; printf "%s", $0; fflush() }'
  apt-get install -y curl 2>&1 | awk '{ printf "\r\033[K   installing curl.. "; printf "%s", $0; fflush() }'
fi
if ! command -v whiptail &> /dev/null; then
  echo "installing whiptail .... "
  apt-get update >/dev/null 2>&1 | awk '{ printf "\r\033[K   updating.. "; printf "%s", $0; fflush() }'
  apt-get install -y whiptail 2>&1 | awk '{ printf "\r\033[K   installing whiptail.. "; printf "%s", $0; fflush() }'
fi
export timezone=$(cat /etc/timezone)
color
start_
