const { XrplClient } = require('xrpl-client')
const lib = require('xrpl-accountlib');
const { decode } = require('xrpl-binary-codec-prerelease');
const { exit } = require('process');
const { createTransport } = require('nodemailer');
//const { ALPN_ENABLED } = require('constants');
const { Console } = require('console');
const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');
dotenv.config({ path: path.resolve(__dirname, '.env') });

// log/console setup  ......................................................................
const verboseLog = process.env.verboseLog === 'true' ? true : false;
const consoleLog = (msg) => {
    console.log(new Date().toISOString() + " " + msg)
}
const logVerbose = (msg) => {
  if (verboseLog) {
    consoleLog(msg)
  }
}

const YW = "\x1b[33m"
const BL = "\x1b[36m"
const RD= "\x1b[01;31m"
const BGN="\x1b[4;92m"
const GN = "\x1b[1;92m"
const DGN = "\x1b[32m"
const CL = "\x1b[m"
const TICK = `${GN}✓${CL}`
const CROSS=`${RD}✗${CL}`

//...............................................................................................................................................................................................
// variable setups  ..............................................................................................................................................................................

const command = process.argv.slice(2)[0];
const run_wallet_setup = process.env.run_wallet_setup === 'true' ? true : false;
const run_transfer_funds = process.env.run_transfer_funds === 'true' ? true : false;
const run_monitor_balance = process.env.run_monitor_balance === 'true' ? true : false;
const run_monitor_heartbeat = process.env.run_monitor_heartbeat === 'true' ? true : false;
const run_monitor_claimreward = process.env.run_monitor_claimreward === 'true' ? true : false;
const use_testnet = process.env.use_testnet === 'true' ? true : false;

const xahSetupamount = process.env.xahSetupamount;
const evrSetupamount = process.env.evrSetupamount;
const evrSetupamount_rep = process.env.evrSetupamount_rep;
const set_regular_key = process.env.set_regular_key === 'true' ? true : false;
const feeStartAmount = process.env.fee;
const auto_adjust_fee = process.env.auto_adjust_fee === 'true' ? true : false;
const fee_adjust_amount = process.env.fee_adjust_amount;
const fee_max_amount = process.env.fee_max_amount;
const minutes_from_last_heartbeat_alert_threshold = process.env.minutes_from_last_heartbeat_alert_threshold;
const alert_repeat_interval_in_minutes = process.env.alert_repeat_interval_in_minutes;
const xah_balance_threshold = process.env.xah_balance_threshold;
const evr_balance_threshold = process.env.evr_balance_threshold;
const minimum_evr_transfer = process.env.minimum_evr_transfer;
const xah_transfer = process.env.xah_transfer === 'true' ? true : false;
const xah_transfer_reserve = process.env.xah_transfer_reserve;
const reputation_transfer = process.env.reputation_transfer === 'true' ? true : false;
const xah_refill_amount = process.env.xah_refill_amount;
const evr_refill_amount = process.env.evr_refill_amount;
let hostMinInstanceCount, hostMaxLeaseAmount, hostReputationThreshold;

let xahaud, network_id, trustlineAddress, heartbeatClient, client;
async function networkSetup(){
  if (use_testnet) {
    logVerbose("using testnet varibles");
    xahaud = await process.env.xahaud_test;
    network = "testnet"
    network_id = "21338";
    trustlineAddress="r9gYbjBfANRfA1JHfaCVfPPGfXYiqQvmhS";
  } else {
    logVerbose("using mainnet varibles");
    xahaud = await process.env.xahaud;
    network = "mainnet"
    network_id = "21337";
    trustlineAddress="rEvernodee8dJLaFsujS6q1EiXvZYmHXr8";
  }
  client = await new XrplClient(xahaud);

  // setup evernode.js.client
  const evernode = require('evernode-js-client');
  await evernode.Defaults.useNetwork(network)
  await evernode.Defaults.set({ rippledServer: xahaud });
  heartbeatClient = await evernode.HookClientFactory.create(evernode.HookTypes.heartbeat);
}

// Notification setup  ...................................................................

const myDate = new Date().toUTCString();

const email_notification = process.env.email_notificatione === 'true' ? true : false;
const smtpKey = process.env.smtpKey;
const smtpEmail = process.env.smtpEmail;
const destinationEmail = process.env.destinationEmail || process.env.smtpEmail;
const transporter = createTransport({
  host: "smtp-relay.sendinblue.com",
  port: 587,
  auth: {
    user: smtpEmail,
    pass: smtpKey,
  },
});

const push_notification = process.env.push_notification === 'true' ? true : false;
const push_addresses = process.env.push_addresses.split('\n');

// account handling  ....................................................................

let accounts = [];
let account_seeds = [];
let keypair = "";
let use_keypair_file = ""; 
let sourceAccount;
let evrDestinationAccount = "";
let evrDestinationAccountTag = "";
let reputationAccounts = [];
let reputationaccount_seeds = [];

async function getAccounts() {
  consoleLog("gettings accounts...");
  use_keypair_file = process.env.use_keypair_file === 'true' ? true : false;
  if ( command == "wallet_setup" ) { use_keypair_file = true };
  const keypair_file = process.env.keypair_file;
  const keypair_rep_file = process.env.keypair_rep_file;
  if (use_keypair_file)  {
    try {
      consoleLog(`using ${keypair_file} for account pairs, with 1st line as sourceAccount`);
      const accountsdata = await fs.promises.readFile(keypair_file, 'utf8');
      accounts = await accountsdata.match(/Address:\s([a-zA-Z0-9]+)/g).map(match => match.split(' ')[1]);
      account_seeds = await accountsdata.match(/Seed:\s([a-zA-Z0-9]+)/g).map(match => match.split(' ')[1]);
    } catch (err) {
      console.error(`Error reading ${key_pair} file:`);
      logVerbose("error returned ->" + err)
    }
    try {
      consoleLog(`and ${keypair_rep_file} for reputation account pairs`);
      const repdata = await fs.promises.readFile(keypair_rep_file, 'utf8');
      reputationAccounts = await repdata.match(/Address:\s([a-zA-Z0-9]+)/g).map(match => match.split(' ')[1]);
      reputationaccount_seeds = await repdata.match(/Seed:\s([a-zA-Z0-9]+)/g).map(match => match.split(' ')[1]);
    } catch (err) {
      console.error(`Error reading ${keypair_rep_file} file:`);
      logVerbose("error returned ->" + err)
    }
    consoleLog("number of accounts found = " + accounts.length);
    consoleLog("number of reputationAccounts found = " + reputationAccounts.length);
    logVerbose(`account strings -->${accounts},\n and reputation accounts -->${reputationAccounts}`);
    logVerbose(`seed strings -->${account_seeds},\n and reputation seeds -->${reputationaccount_seeds}`);
    sourceAccount = accounts[0];
    evrDestinationAccount = accounts[0];
    evrDestinationAccountTag = "";
    try {
      var secret = account_seeds[0];
      keypair = lib.derive.familySeed(secret);
    } catch (err) {
      console.error(`Error reading secret from source account`);
      logVerbose("error returned ->" + err)
    }

  } else {
    consoleLog("using .env file for source Account, accounts, reputation accounts, and regular key for their access.");
    sourceAccount = process.env.sourceAccount;
    evrDestinationAccount = process.env.evrDestinationAccount;
    evrDestinationAccountTag = process.env.evrDestinationAccountTag;
    accounts = process.env.accounts.split('\n');
    consoleLog("number of accounts found = " + accounts.length);
    if (process.env.secret) {
      var secret = process.env.secret;
      keypair = lib.derive.familySeed(secret);
    } else {
      console.error('Error reading secret from .env file');
      process.exit();
    }
    if(await process.env.reputationAccounts != "") {
      reputationAccounts = process.env.reputationAccounts.split('\n');
    }
    consoleLog("number of reputationAccounts found = " + reputationAccounts.length);
    logVerbose(`account strings -->${accounts},\n and reputation accounts -->${reputationAccounts}`);
    logVerbose(`sourceAccount -->${sourceAccount},\n and secret -->${secret}`);
  }
}


//...............................................................................................................................................................................................
// balance_monitor  .............................................................................................................................................................................

async function monitor_balance(){
  console.log(" ---------------- ");
  consoleLog("Starting Balance Monitor module....");
  
  tesSUCCESS = "true"
  var accountIndex = 1;
  var feeAmount = feeStartAmount;
  var sequence = 0;
  var totalEVR = 0;
  var totalXAH = 0;
  if (reputationAccounts.length != 0 ) {
    var allAccounts = accounts.concat(reputationAccounts);
  } else {
    consoleLog("no reputation accounts to check")
    var allAccounts = accounts;
  }
  consoleLog("checking XAH levels on all " + accounts.length + " accounts and " + reputationAccounts.length + " reputation accounts, with total amount of " + allAccounts.length + " to check...");
  logVerbose(`allAccounts --> ${allAccounts}`);
  console.log(" ------- ");
  console.log(" ");

  for (const account of allAccounts) {
    try {
      var { account_data } = await client.send({ command: "account_info", account: account });
      var sourceData = await client.send({ command: "account_info", account: sourceAccount });
      var sequence = sourceData.account_data.Sequence;
    } catch (err){
      console.error(`Error getting account info, has account(${account}) and sourceAccount(${sourceAccount}) been activated yet? is ${network} the correct network?`);
      logVerbose("error returned ->" + err);
      tesSUCCESS = false;
      continue
    }

    if (account != sourceAccount) {
      if (reputationAccounts.includes(account)) {
        var accountType = "reputation account"
      } else {
        var accountType = "evernode account";
        totalEVR = ( totalEVR + ( await GetEvrBalance(account)) );
      }
      if (Number(account_data?.Balance) < (xah_balance_threshold * 1000000) ) {
        const filePath = path.resolve(__dirname, 'balanceLow-' + account + '.txt');
        consoleLog(`${YW}XAH Balance for ${accountType} ${accountIndex}, ${account} is ${(account_data?.Balance / 1000000)}, below threshold of ${xah_balance_threshold}, sending ${xah_refill_amount}XAH${CL}`);
        consoleLog(`Source account XAH balance = ${(sourceData?.account_data?.Balance / 1000000)}`);
        if ((sourceData?.account_data?.Balance / 1000000) < xah_refill_amount) {
          consoleLog(`${RD}Not enough XAH funds in source account to fill other accounts${CL}`);
          if (!fs.existsSync(filePath) && email_notification) {
            await sendMail("Insufficient XAH funds", "We tried to send XAH to " + account + " but the source balance in " + sourceAccount + " is too low.\r\n\r\nPlease feed your source account.");
            fs.writeFileSync(filePath, "Balance is too low");
          }
        }
        else {
          let xahRefillTx = {
            TransactionType: 'Payment',
            Account: sourceAccount, 
            Amount: (xah_refill_amount * 1000000).toString(),
            Destination: account_data.Account, 
            DestinationTag: evrDestinationAccountTag,
            NetworkID: network_id,
            Sequence: sequence
          }
          // auto fee calculations and submit
          feeResponse = await client.send({ command: 'fee', xahRefillTx});
          if ( Number(feeResponse.drops.open_ledger_fee) > feeStartAmount && Number(feeResponse.drops.open_ledger_fee) > Number(feeResponse.drops.base_fee) && auto_adjust_fee == true ) { feeAmount = ( Number(feeResponse.drops.open_ledger_fee) + Number(fee_adjust_amount) ).toString() } else { feeAmount = feeResponse.drops.base_fee };
          if ( auto_adjust_fee == true && Number(feeAmount) < fee_max_amount ){
            xahRefillTx["Fee"] = feeAmount;
            const { signedTransaction: xahRefillTxSigned } = lib.sign(xahRefillTx, keypair);
            var { engine_result: xahRefillTxResult }  = await client.send({ command:'submit', 'tx_blob': xahRefillTxSigned });
            logVerbose(`\nfee auto adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} feeResponse:${feeResponse.drops.open_ledger_fee} xahRefillTxTx:${JSON.stringify(xahRefillTx)}`);
          } else {
            if ( auto_adjust_fee == true ) { consoleLog(`${YW}maxfee limit reached, swapping to waiting for ledger end for fee calculations${CL}`) };
            networkInfo = await lib.utils.txNetworkAndAccountValues(xahaud, sourceAccount);
            xahRefillTx = { ...xahRefillTx, ...networkInfo.txValues };
            var { response: { engine_result: xahRefillTxResult } }  = await lib.signAndSubmit(xahRefillTx, xahaud, keypair);
            logVerbose(`\nfee no adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} feeResponse:${feeResponse.drops.open_ledger_fee} xahRefillTxTx:${JSON.stringify(xahRefillTx)}`);
          }

          if ( xahRefillTxResult !== "tesSUCCESS" && xahRefillTxResult !== "terQUEUED" ) {
            tesSUCCESS = false;
            consoleLog(`${RD}XAH refill FAILED TO SEND, ${(xah_refill_amount)} XAH ${sourceAccount} > xx ${account_data.Account} (fee:${xahRefillTx.Fee}), result: ${xahRefillTxResult}${CL}`);
          } else {   
            consoleLog(`${GN}XAH refill payment sent, ${(xah_refill_amount)} XAH, ${sourceAccount} --> ${account_data.Account} (fee:${xahRefillTx.Fee}), result: ${xahRefillTxResult}${CL}`);
            totalXAH = ( totalXAH + Number(account_data?.Balance / 1000000) + xah_refill_amount )
          };

          if (fs.existsSync(filePath)) fs.rmSync(filePath);

        }
      } else {
        consoleLog(`Balance for ${accountType} ${accountIndex}, ${account} is ${(account_data?.Balance / 1000000)} above the threshold of ${(xah_balance_threshold)}`);
        totalXAH = ( totalXAH + Number(account_data?.Balance / 1000000) )
      }
    } else {
      consoleLog(`account ${accountIndex}, ${account} is the source account, skipping...`)
    }
    accountIndex++;
    console.log(" ------- ");
  }
  
  if (reputationAccounts != [] ) {
    console.log("")
    console.log(" ------- ");
    console.log("")
    consoleLog("checking EVR levels on " + reputationAccounts.length + " reputation accounts...");
    consoleLog(" ------- ");
    accountIndex = 1;
    for (const account of reputationAccounts) {

      try {
        const { account_data } = await client.send({ command: "account_info", account: account });
        var sourceData = await client.send({ command: "account_info", account: sourceAccount });
        var sequence = sourceData.account_data.Sequence;
      } catch (err){
        console.error(`Error getting account info, has account(${account}) and sourceAccount(${sourceAccount}) been activated yet? is ${network} the correct network?`);
        logVerbose("error returned ->" + err);
        tesSUCCESS = false;
        continue
      }

      if (account != sourceAccount) {
        var evrBalance = await GetEvrBalance(account);
        var sourceBalance = await GetEvrBalance(sourceAccount);
        logVerbose(`EVR Balance for source account ${sourceAccount} is ${sourceBalance}`);

        if (( evrBalance < evr_balance_threshold )) {
          const filePath = path.resolve(__dirname, 'balanceLow-' + account + '.txt');
          consoleLog(`${YW}EVR balance on reputation account ${accountIndex}, ${account} is ${evrBalance}, below threshold of ${evr_balance_threshold}, sending ${evr_refill_amount} EVR${CL}`);
          
          if (sourceBalance < evr_refill_amount) {
            consoleLog(`${RD}Not enough funds in source account ${sourceAccount} to fill accounts with EVR${CL}`);
            logVerbose("Source Account EVR Balance " + sourceBalance);
            logVerbose("evr_refill_amount =  " + evr_refill_amount);
            if (!fs.existsSync(filePath) && email_notification) {
              await sendMail("Insufficient EVR funds", "We tried to send EVR to " + account + " but the balance in " + sourceAccount + " is too low.\r\n\r\nPlease feed your source account.");
              fs.writeFileSync(filePath, "EVR Balance is too low");
            }
          }
          else {
            let evrRefillTx = { 
              TransactionType: 'Payment',
              Account: sourceAccount,  //Destination account
              Amount: {
                "currency": "EVR",
                "value": evr_refill_amount,
                "issuer": trustlineAddress 
              },
              Destination: account, //the account that has to be filled
              DestinationTag: evrDestinationAccountTag, 
              NetworkID: network_id,
              Sequence: sequence
            }
            // auto fee calculations and submit
            feeResponse = await client.send({ command: 'fee', evrRefillTx});
            if ( Number(feeResponse.drops.open_ledger_fee) > feeStartAmount && Number(feeResponse.drops.open_ledger_fee) > Number(feeResponse.drops.base_fee) && auto_adjust_fee == true ) { feeAmount = ( Number(feeResponse.drops.open_ledger_fee) + Number(fee_adjust_amount) ).toString() } else { feeAmount = feeResponse.drops.base_fee };
            if ( auto_adjust_fee == true && Number(feeAmount) < fee_max_amount ){
              evrRefillTx["Fee"] = feeAmount;
              const { signedTransaction: evrRefillTxSigned } = lib.sign(evrRefillTx, keypair);
              var { engine_result: evrRefillTxResult }  = await client.send({ command:'submit', 'tx_blob': evrRefillTxSigned });
              logVerbose(`\nfee auto adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} feeResponse:${feeResponse.drops.open_ledger_fee} evrRefillTxTx:${JSON.stringify(evrRefillTx)}`);
            } else {
              if ( auto_adjust_fee == true ) { consoleLog(`${YW}maxfee limit reached, swapping to waiting for ledger end for fee calculations${CL}`) };
              networkInfo = await lib.utils.txNetworkAndAccountValues(xahaud, sourceAccount);
              evrRefillTx = { ...evrRefillTx, ...networkInfo.txValues };
              var { response: { engine_result: evrRefillTxResult } }  = await lib.signAndSubmit(evrRefillTx, xahaud, keypair);
              logVerbose(`\nfee no adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} feeResponse:${feeResponse.drops.open_ledger_fee} evrRefillTxTx:${JSON.stringify(evrRefillTx)}`);
            }

            if ( evrRefillTxResult !== "tesSUCCESS" && evrRefillTxResult !== "terQUEUED" ) {
              tesSUCCESS = false;
              consoleLog(`${RD}EVR Refill FAILED TO SEND, ${evr_refill_amount} EVR ${sourceAccount} > xx ${account} (fee:${evrRefillTx.Fee}), result: ${evrRefillTxResult}${CL}`);
            } else {   
            consoleLog(`${GN}EVR Refill sent, ${evr_refill_amount} EVR, ${sourceAccount} --> ${account} (fee:${evrRefillTx.Fee}), result: ${evrRefillTxResult}${CL}`);
            totalEVR = ( totalEVR + evrBalance + evr_refill_amount );
            };

            if (fs.existsSync(filePath)) fs.rmSync(filePath);
          }
        } else {
          consoleLog(`EVR balance for ${accountType} ${accountIndex}, ${account} is ${evrBalance} above the evr_balance_threshold of ${evr_balance_threshold}`);
          totalEVR = ( totalEVR + evrBalance );
        }
        
      }
      accountIndex++;
      consoleLog(" ------- ");
    }

  }
  console.log(" ");
  console.log(" ---------------- ");
  if (tesSUCCESS){
    var sourceData = await client.send({ command: "account_info", account: sourceAccount });
    let XAHsourceBalance = sourceData?.account_data?.Balance ?? 0;
    totalXAH = Number(totalXAH+(XAHsourceBalance/1000000));
    totalEVR = Number(totalEVR+(await GetEvrBalance(sourceAccount)));
    logVerbose(`${XAHsourceBalance} -- ${totalXAH} -- ${totalEVR} -- `);
    consoleLog(`${GN}all accounts successfully checked${CL}`);
    consoleLog(`${GN}your total XAH amount in all accounts = ${totalXAH.toFixed(4)} XAH${CL}`);
    consoleLog(`${GN}your total EVR amount in all accounts = ${totalEVR.toFixed(4)} EVR${CL}`);
    consoleLog(" ---------------- ");
    consoleLog(" ");
    return 0
  } else {
    consoleLog(`${RD}there was a fault in querying 1 or more accounts, scroll up to find out more${CL}`)
    consoleLog(" ---------------- ");
    consoleLog(" ");
    return 1
  }
}

//.................................................................................................................................................................................................
// transfer_funds / fund Sweeper  .................................................................................................................................................................

async function transfer_funds(){
  console.log(" ---------------- ");
  consoleLog("Starting the funds transfer module...");
  var accountIndex = 1

  if (reputation_transfer) {
    logVerbose("reputation accounts will be checked too")
    var allAccounts = accounts.concat(reputationAccounts);
  } else {
    logVerbose("reputation accounts not being checked")
    var allAccounts = accounts;
  }
  consoleLog("checking " + allAccounts.length + " accounts...");
  logVerbose(`allAccounts --> ${allAccounts}\n`);

  for (const account of allAccounts) {
    if (reputationAccounts.includes(account)) { var accountType = "reputation account" } else { var accountType = "evernode account" };
    consoleLog(`start the transferring process on ${accountType} ${accountIndex}, ${account}`);
    accountIndex++;
    if (account != evrDestinationAccount) {
      try {
        var tesSUCCESS = true;
        var attempt = 1;
        var feeAmount = feeStartAmount;
        var { account_data } = await client.send({ command: "account_info", account })
      } catch (err){
        console.error(`Error getting account info, has the account(${account}) been activated yet? is ${network} the correct network?`);
        logVerbose("error returned ->" + err);
        tesSUCCESS = false;
        continue
      }

      while (true) {

        // sweep XAH
        if ( process.env.xah_transfer == "true" && Number(account_data?.Balance) > Number(xah_transfer_reserve * 1000000) ) {
          let xahTx = {
            TransactionType: 'Payment',
            Account: account,
            Amount: (account_data?.Balance - (xah_transfer_reserve * 1000000)).toString(),
            Destination: evrDestinationAccount,
            NetworkID: network_id,
            Sequence: account_data.Sequence++
          };

          // auto fee calculations and submit
          feeResponse = await client.send({ command: 'fee', xahTx});
          if ( Number(feeResponse.drops.open_ledger_fee) > feeStartAmount && Number(feeResponse.drops.open_ledger_fee) > Number(feeResponse.drops.base_fee) && auto_adjust_fee == true ) { feeAmount = ( Number(feeResponse.drops.open_ledger_fee) + Number(fee_adjust_amount) ).toString() } else { feeAmount = feeResponse.drops.base_fee };
          if ( auto_adjust_fee == true && Number(feeAmount) < fee_max_amount ){
            xahTx["Fee"] = feeAmount;
            const { signedTransaction: xahTxSigned } = lib.sign(xahTx, keypair);
            var { engine_result: xahResult }  = await client.send({ command:'submit', 'tx_blob': xahTxSigned });
            logVerbose(`\nfee auto adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} feeResponse:${feeResponse.drops.open_ledger_fee} xahTx:${JSON.stringify(xahTx)}`);
          } else {
            if ( auto_adjust_fee == true ) { consoleLog(`${YW}maxfee limit reached, swapping to waiting for ledger end for fee calculations${CL}`) };
            networkInfo = await lib.utils.txNetworkAndAccountValues(xahaud, account);
            xahTx = { ...xahTx, ...networkInfo.txValues };
            var { response: { engine_result: xahResult } }  = await lib.signAndSubmit(xahTx, xahaud, keypair);
            logVerbose(`\nfee no adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} feeResponse:${feeResponse.drops.open_ledger_fee} xahTx:${JSON.stringify(xahTx)}`);
          }

          if ( xahResult !== "tesSUCCESS" && xahResult !== "terQUEUED" ) {
            tesSUCCESS = false;
            consoleLog(`${RD}XAH paymentSweep FAILED TO SEND, ${((account_data?.Balance - (xah_transfer_reserve * 1000000)) / 1000000)} XAH ${account} > xx ${evrDestinationAccount} (fee:${xahTx.Fee}), result: ${xahResult}${CL}`);
          } else {   
          consoleLog(`${GN}XAH paymentSweep sent, ${((account_data?.Balance - (xah_transfer_reserve * 1000000)) / 1000000)} XAH ${account} --> ${evrDestinationAccount} (fee:${xahTx.Fee}), result: ${xahResult}${CL}`);
          };

        } else {
          if (xah_transfer) {
            consoleLog(`${YW}XAH Balance is ${(account_data?.Balance / 1000000 )} XAH, below the reserve of ${xah_transfer_reserve} XAH, set in .env file, skipping account...${CL}`);
          } else {
            consoleLog(`${YW}XAH Balance is ${(account_data?.Balance / 1000000 )} XAH, XAH sweep is set to false, skipping account...${CL}`);
          }

        }

        var evrBalance = await GetEvrBalance(account);

        // check if the EVR balance is enough to sweep
        if (evrBalance <= minimum_evr_transfer) {
          consoleLog(`${YW}EVR Balance is ${evrBalance} EVR, below minimum required of ${minimum_evr_transfer} to sweep EVR funds, skipping account...${CL}`);
        } else {
          // sweep EVR to evrDestinationAccount
          let evrTx = {
            TransactionType: 'Payment',
            Account: account,
            Amount: {
              "currency": "EVR",
              "value": evrBalance,
              "issuer": trustlineAddress
            },
            Destination: evrDestinationAccount,
            DestinationTag: evrDestinationAccountTag,
            NetworkID: network_id,
            Sequence: account_data.Sequence++
          }

          // auto fee calculations and submit
          feeResponse = await client.send({ command: 'fee', evrTx});
          if ( Number(feeResponse.drops.open_ledger_fee) > feeStartAmount && Number(feeResponse.drops.open_ledger_fee) > Number(feeResponse.drops.base_fee) && auto_adjust_fee == true ) { feeAmount = ( Number(feeResponse.drops.open_ledger_fee) + Number(fee_adjust_amount) ).toString() } else { feeAmount = feeResponse.drops.base_fee };
          if ( auto_adjust_fee == true && Number(feeAmount) < fee_max_amount ){
            evrTx["Fee"] = feeAmount;
            const { signedTransaction: evrTxSigned } = lib.sign(evrTx, keypair);
            var { engine_result: evrResult }  = await client.send({ command:'submit', 'tx_blob': evrTxSigned });
            logVerbose(`\nfee auto adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} feeResponse:${feeResponse.drops.open_ledger_fee} xahTx:${JSON.stringify(evrTx)}`);
          } else {
            if ( auto_adjust_fee == true ) { consoleLog(`${YW}maxfee limit reached, swapping to waiting for ledger end for fee calculations${CL}`) };
            networkInfo = await lib.utils.txNetworkAndAccountValues(xahaud, account);
            evrTx = { ...evrTx, ...networkInfo.txValues };
            var { response: { engine_result: evrResult } }  = await lib.signAndSubmit(evrTx, xahaud, keypair);
            logVerbose(`\nfee no adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} feeResponse:${feeResponse.drops.open_ledger_fee} xahTx:${JSON.stringify(evrTx)}`);
          }

          if ( evrResult !== "tesSUCCESS" && evrResult !== "terQUEUED" ) {
            tesSUCCESS = false;
            consoleLog(`${RD}EVR paymentSweep FAILED TO SEND, ${evrBalance} EVR ${account} > xx ${evrDestinationAccount} (fee:${evrTx.Fee}), result: ${evrResult}${CL}`);
          } else {   
          consoleLog(`${GN}EVR paymentSweep sent, ${evrBalance} EVR, ${account} --> ${evrDestinationAccount} (fee:${evrTx.Fee}), result: ${evrResult}${CL}`);
          };
        }

        if ( tesSUCCESS == true ) {
          break 
        } else { 
          attempt++;
          if ( attempt > 2 ) { process.exit() };
          logVerbose(`${RD}\nsomething failed, retying, ${attempt} of 2${CL}`);
        };
      }

    } else {
      logVerbose("skipping as its the source account.");
    };
    consoleLog(" ---------------- ");
    consoleLog(" ");
  }
  if (tesSUCCESS){
    consoleLog(`${GN}all accounts successfully checked${CL}`)
    consoleLog(" ---------------- ");
    consoleLog(" ");
    return 0
  } else {
    consoleLog(`${RD}there was a fault in querying 1 or more accounts, scroll up to find out more${CL}`)
    consoleLog(" ---------------- ");
    consoleLog(" ");
    return 1
  }
}

//.................................................................................................................................................................................................
// monitor_heartbeat  .............................................................................................................................................................................

async function monitor_heartbeat() {
  console.log(" ---------------- ");
  consoleLog("Checking account heartbeats...");
  heartbeatClientstatus = await heartbeatClient.connect();
  hostMinInstanceCount = await heartbeatClient.config.rewardConfiguration.hostMinInstanceCount
  hostMaxLeaseAmount = await parseFloat(heartbeatClient.config.rewardInfo.hostMaxLeaseAmount)
  hostReputationThreshold = await heartbeatClient.config.rewardConfiguration.hostReputationThreshold
  logVerbose("connecting to ledger/evernode registry, status:" + heartbeatClientstatus);
  consoleLog("Evernode Info, Minimum instance count at :" + hostMinInstanceCount + " Max Lease amount at :" + hostMaxLeaseAmount + " and Reputation threshold is at:" + hostReputationThreshold)
  consoleLog(" ---------------- ");

  var accountIndex = 1;
  if (use_keypair_file) { var sliceAmount = 1 } else { var sliceAmount = 0 };
  for (const account of accounts.slice(sliceAmount)) {
    consoleLog("checking account heartbeat on account " + accountIndex + ", " + account);
    await checkAccountHeartBeat(account, accountIndex);
    accountIndex++;
    consoleLog(" ---------------- ");
  }
  heartbeatClientstatus = await heartbeatClient.disconnect();
  logVerbose("all finished, disconnecting from ledger/evernode registry, status:" + heartbeatClientstatus);
}

function getMinutesBetweenDates(startDate, endDate) {
  const diff = endDate - startDate;
  return (diff / 60000);
}

async function checkAccountHeartBeat(account, accountIndex) {
  const filePath = path.resolve(__dirname, account + '.txt');
  var ledgerIndex = -1;
  var faultReason = "noFault"
  var accountFailed = fs.existsSync(filePath);
  var date_failure = new Date();
  if (accountFailed) {
    date_failure = new Date(Date.parse(fs.readFileSync(filePath, 'utf8')));
    logVerbose("account " + account + " is in status failed since " + date_failure);
    const diffMinutes = getMinutesBetweenDates(date_failure, new Date());
    logVerbose("diffMinutes = " + diffMinutes);
    logVerbose("alert_repeat_interval_in_minutes = " + alert_repeat_interval_in_minutes);
    if (alert_repeat_interval_in_minutes > 0 && diffMinutes > alert_repeat_interval_in_minutes) {
      accountFailed = false;
    }
  }

  const hostInfo = await heartbeatClient.getHostInfo(account);
  let currentTimestamp = Math.floor(Date.now() / 1000);
  logVerbose("time now -->" + currentTimestamp);

  if (!hostInfo) {
    var faultReason = "fault";
    consoleLog(`${RD}no hostInfo available...${CL}`);
    await handleFailure(account, accountFailed, filePath, accountIndex, hostInfo, "no information available", faultReason);
    return;
  };

  logVerbose(`full hostInfo -->${JSON.stringify(hostInfo)}`);
  const daysElapsed = Math.floor((currentTimestamp - hostInfo.lastHeartbeatIndex) / (3600 * 24));
  const hoursElapsed = Math.floor(((currentTimestamp - hostInfo.lastHeartbeatIndex)% (3600 * 24)) / 3600);
  const minutesElapsed = Math.floor(((currentTimestamp - hostInfo.lastHeartbeatIndex) % 3600) / 60);
  var hostInfoSTR = `last heartbeat ${daysElapsed} days ${hoursElapsed} hours and ${minutesElapsed} minutes ago, activeInstances:${hostInfo.activeInstances} maxInstances:${hostInfo.maxInstances} (>=${hostMinInstanceCount}), leaseAmount ${hostInfo.leaseAmount} (<${hostMaxLeaseAmount}), reputation ${hostInfo.hostReputation} (>=${hostReputationThreshold})`
  
  if (currentTimestamp - hostInfo.lastHeartbeatIndex > 60 * minutes_from_last_heartbeat_alert_threshold) {
    var faultReason = "heartbeat";
    consoleLog(`${hostInfoSTR}`);
    consoleLog(`${CROSS} ${RD}heartbeat failure detected${CL}`);
  };
  if ((hostInfo.maxInstances < hostMinInstanceCount) || (hostInfo.leaseAmount > hostMaxLeaseAmount) || (hostInfo.hostReputation < hostReputationThreshold)) {
    if ( faultReason == "heartbeat" ) {
      var faultReason = "heartbeat+reputation";
      consoleLog(`${CROSS} ${RD}and reputation fault detected${CL}`);
    } else { 
      var faultReason = "reputation"
      consoleLog(`${hostInfoSTR}`);
      consoleLog(`${CROSS} ${YW}reputation fault detected${CL}`);
    };
  };

  if (faultReason == "noFault" ) {
    consoleLog(`${TICK}${GN} heartbeat, and all reputation stats check out ok${CL},`);
    consoleLog(`${hostInfoSTR}`);
    if (fs.existsSync(filePath)) {
      await sendSuccess(account, accountIndex, hostInfo, hostInfoSTR);
      fs.rmSync(filePath);
    } else if (push_notification) { await sendSuccess(account, accountIndex, hostInfo, hostInfoSTR) };

  } else {
    await handleFailure(account, accountFailed, filePath, accountIndex, hostInfo, hostInfoSTR, faultReason );
  }
}

// HEARTBEAT failure handling  ........................................................................................................................................................................

async function handleFailure(account, accountFailed, filePath, accountIndex, hostInfo, hostInfoSTR, faultReason) {
  if (!accountFailed) {
    await sendFailure(account, accountIndex, hostInfo, hostInfoSTR, faultReason);
    fs.writeFileSync(filePath, new Date().toString());
  } else if (push_notification) { await sendFailure(account, accountIndex, hostInfo, hostInfoSTR, faultReason) };
  consoleLog(`${CROSS}${RD} ALERT, DETECTED A EVERNODE FAULT DUE TO, ${faultReason}${CL}`);
}

// HEARTBEAT send Notifications  ........................................................................................................................................................................

async function sendFailure(account, accountIndex, hostInfo, hostInfoSTR, faultReason) {
  if ( faultReason == "fault" ) {
    var subject = "Fault in Evernode monitor on " + accountIndex.toString();
    var text = "Fault in Evernode monitor account " + account + " (" + accountIndex.toString() + ")";
  } else if ( faultReason == "heartbeat" ) {
    var subject = "Failure in Evernode heartbeat on " + hostInfo.domain;
    var text = "Failure in retrieving Evernode heartbeat for account " + account + " (" + accountIndex.toString() + ")\n with domain ${hostInfo.domain}\n\n full info ${hostInfo}";
  } else {
    var subject = "problem in Evernode monitor stats, on account " + hostInfo.domain;
    var text = "problem with a ruputation stat for account " + account + " (" + accountIndex.toString() + ")\n with domain ${hostInfo.domain}\n\n stats ${faultInfo}\nfull info ${hostInfo}";
  };
  logVerbose(`sending notification, faultInfo: ${faultReason}, ${hostInfoSTR}`);
  if (email_notification) { await sendMail(subject, text) };
  if (push_notification) { await sendPush(account, accountIndex, "down", `${faultReason}, ${hostInfoSTR}` ) } ;
}

async function sendSuccess(account, accountIndex, hostInfo, hostInfoSTR) {
  var subject = "Evernode heartbeat monitor restored " +  accountIndex.toString();
  var text = "Evernode heartbeat monitor restored in account " + account + " (" + accountIndex.toString() + ")";
  if (email_notification) { await sendMail(subject, text) };
  if (push_notification) { await sendPush(account, accountIndex, "up", hostInfoSTR) } ;
}

async function sendMail(subject, text) {
  var mailOptions = {
    from: smtpEmail,
    to: destinationEmail,
    subject: subject,
    text: text
  };
  consoleLog("SENDING MAIL " + JSON.stringify(mailOptions));

  if (!smtpEmail) {
    consoleLog("smtp email not set in .env file. Email is not sent");
    return;
  }

  await transporter.sendMail(mailOptions, function (error, info) {
    if (error) {
      consoleLog(error);
    } else {
      consoleLog('Email sent: ' + info.response);
    }
  });
}

async function sendPush(account, accountIndex, pushStatus, pushMSG) {
  pushURL = push_addresses[accountIndex - 1];
  if ( typeof pushURL === 'undefined' ) { consoleLog(`${RD}no push_address found (account Index ${accountIndex})${CL}`); return };
  fetchURL = pushURL + "?status=" + pushStatus + "&msg=" + pushMSG;
  logVerbose("fetchURL ->" + fetchURL)
  try {
    const fetchResponse = await fetch(fetchURL);
    if (!fetchResponse.ok) {
      consoleLog(`${RD}push notification NOT being received by robot :${fetchResponse.statusText}${CL}`);
    } else {
    consoleLog(`push notification received by robot :${GN}${await fetchResponse.ok}${CL}`);
    }
  } catch (error) {
    consoleLog(`${RD}There was a problem with sending push notification to robot URL, error: ${error}${CL}`);
  }
}

//...............................................................................................................................................................................................
// wallet_setup  ................................................................................................................................................................................

async function wallet_setup(){
  console.log(" ---------------- ");
  consoleLog("Starting initial wallet module...");

  var feeAmount = feeStartAmount;
  var feeResponse = {};
  var networkInfo = {};
  var loop = 0;

  if (reputationAccounts.length != "0" ) {
    var allAccounts = accounts.concat(reputationAccounts);
    var allAccount_seeds = account_seeds.concat(reputationaccount_seeds);
  } else {
    logVerbose("no reputation accounts found")
    var allAccounts = accounts;
    var allAccount_seeds = account_seeds;
  }
  consoleLog("checking " + allAccounts.length + " accounts...");
  logVerbose(`allAccounts --> ${allAccounts}\n allAccount_seeds -->${allAccount_seeds}`);

  for (const account of allAccounts) {
    consoleLog("running initial wallet setup on account " + loop + " : " + account);
    
    if (account != sourceAccount) {
      var tesSUCCESS = true;
      var attempt = 1;

      while (true) {

        // Send xahSetupamount XAH ( activating account )
        if (xahSetupamount != 0){
          try {
            var { account_data: { Sequence: sequence } } = await client.send({ command: "account_info", account: sourceAccount });
          } catch (err){
            console.error(`Error getting sequence number of source account, has the sourceAccount(${sourceAccount}) been activated yet? is ${network} the correct network?`);
            logVerbose("error returned ->" + err);
            tesSUCCESS = false;
            break
          }
          let xahTx = {
           TransactionType: 'Payment',
            Account: sourceAccount,
            Amount: (xahSetupamount * 1000000).toString(),
            Destination: account,
            NetworkID: network_id,
            Sequence: sequence
          };

          // auto fee calculations and submit
          feeResponse = await client.send({ command: 'fee' });
          if ( Number(feeResponse.drops.open_ledger_fee) > feeStartAmount && Number(feeResponse.drops.open_ledger_fee) > Number(feeResponse.drops.base_fee) && auto_adjust_fee == true ) { feeAmount = ( Number(feeResponse.drops.open_ledger_fee) + Number(fee_adjust_amount) ).toString() } else { feeAmount = feeResponse.drops.base_fee };
          if ( auto_adjust_fee == true && Number(feeAmount) < fee_max_amount ){
            xahTx["Fee"] = feeAmount;
            const { signedTransaction: xahTxSigned } = lib.sign(xahTx, keypair);
            var { engine_result: xahResult }  = await client.send({ command:'submit', 'tx_blob': xahTxSigned });
            logVerbose(`\nfee auto adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${Number(fee_max_amount)} fee_open_ledger_fee:${Number(feeResponse.drops.open_ledger_fee)} fee_base_fee:${feeResponse.drops.base_fee}`);
          } else {
            if ( auto_adjust_fee == true ) { consoleLog(`${YW}maxfee limit reached, swapping to waiting for ledger end for fee calculations${CL}`) };
            networkInfo = await lib.utils.txNetworkAndAccountValues(xahaud, sourceAccount);
            xahTx = { ...xahTx, ...networkInfo.txValues };
            var { response: { engine_result: xahResult } }  = await lib.signAndSubmit(xahTx, xahaud, keypair);
            logVerbose(`\nfee NO adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} fee_open_ledger_fee:${feeResponse.drops.open_ledger_fee} fee_base_fee:${feeResponse.drops.base_fee}`);
          }

          if ( xahResult !== "tesSUCCESS" && xahResult !== "terQUEUED" ) {
            tesSUCCESS = false;
            consoleLog(`${RD}${xahSetupamount}XAH FAILED TO SEND, ${sourceAccount} xxx ${account} (fee:${xahTx.Fee}), result: ${xahResult}${CL}`);
          } else {   
          consoleLog(`${GN}${xahSetupamount} XAH sent, ${sourceAccount} --> ${account} (fee:${xahTx.Fee}), result: ${xahResult}${CL}`);
          };
        }

        // Set trustline and send tokens
        if (reputationAccounts.includes(account)) { var evrAmount = evrSetupamount_rep } else { var evrAmount = evrSetupamount };
        if (evrAmount != 0 && tesSUCCESS == true) {
          try { 
            var { account_data: { Sequence: sequence } } = await client.send({ command: "account_info", account: account });
            let trustlineTx = {
              TransactionType: 'TrustSet',
              Account: account,
              LimitAmount: {
                currency: 'EVR',
                value: '73000000',
                issuer: trustlineAddress
              },
              NetworkID: network_id,
              Sequence: sequence
            };

            // auto fee calculations and submit
            feeResponse = await client.send({ command: 'fee' });
            if ( Number(feeResponse.drops.open_ledger_fee) > feeStartAmount && Number(feeResponse.drops.open_ledger_fee) > Number(feeResponse.drops.base_fee) && auto_adjust_fee == true ) { feeAmount = ( Number(feeResponse.drops.open_ledger_fee) + Number(fee_adjust_amount) ).toString() } else { feeAmount = feeResponse.drops.base_fee };
            if ( auto_adjust_fee == true && Number(feeAmount) < fee_max_amount ){
              trustlineTx["Fee"] = feeAmount;
              try {
                var trustlineKeypair = lib.derive.familySeed(allAccount_seeds[loop]);
              } catch (err) {
                console.error(`Error reading secret for account ${loop} : ${account}`);
                logVerbose("error returned ->" + err)
              }
              const { signedTransaction: trustlineTxSigned } = lib.sign(trustlineTx, trustlineKeypair);
              var { engine_result: trustlineResult } = await client.send({ command: 'submit', 'tx_blob': trustlineTxSigned });
              logVerbose(`\nfee auto adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} fee_open_ledger_fee:${feeResponse.drops.open_ledger_fee} fee_base_fee:${feeResponse.drops.base_fee}`);
            } else {
              if ( auto_adjust_fee == true ) { consoleLog(`${YW}maxfee limit reached, swapping to waiting for ledger end for fee calculations${CL}`) };
              networkInfo = await lib.utils.txNetworkAndAccountValues(xahaud, account);
              trustlineTx = { ...trustlineTx, ...networkInfo.txValues };
              try {
                var trustlineKeypair = lib.derive.familySeed(allAccount_seeds[loop]);
              } catch (err) {
                console.error(`Error reading secret for account ${loop} : ${account}`);
                logVerbose("error returned ->" + err)
              }
              var { response: { engine_result: trustlineResult } } = await lib.signAndSubmit(trustlineTx, xahaud, trustlineKeypair);
              logVerbose(`\nfee NO adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} fee_open_ledger_fee:${feeResponse.drops.open_ledger_fee} fee_base_fee:${feeResponse.drops.base_fee}`);
            }

            if ( trustlineResult !== "tesSUCCESS" && trustlineResult !== "terQUEUED" ) { 
              tesSUCCESS = false;
              consoleLog(`${RD}EVR trustline FAILED TO SET on ${account} (fee:${trustlineTx.Fee}), result: ${trustlineResult}${CL}`);
            } else {
              consoleLog(`${GN}EVR trustline set on ${account} (fee:${trustlineTx.Fee}), result: ${trustlineResult}${CL}`);
            }
          } catch (err) {
            console.error(`Error setting trustline, has this account been activated with XAH yet? xahSetupamount set to ${xahSetupamount}`);
            logVerbose("error returned ->" + err);
            tesSUCCESS = false;
          };

          //wait for trustline to be established
          if (tesSUCCESS) {
            var truslineEstablished = false
            while (truslineEstablished == false) {
              const lines = await client.send({ command: 'account_lines', account })
              logVerbose(`found ${lines.lines.length} trustline on account, checking for issuer ${trustlineAddress}`)
              lines.lines.forEach(t => {
                if (t.account == trustlineAddress) {
                  truslineEstablished = true
                }
              })
            }

            // Send EVR tokens
            const { account_data: { Sequence: sequence } } = await client.send({ command: "account_info", account: sourceAccount });
            let tokenTx = {
              TransactionType: 'Payment',
              Account: sourceAccount,
              Amount: {
                "currency": "EVR",
                "value": evrAmount,
                "issuer": trustlineAddress
              },
              Destination: account,
              DestinationTag: "",
              NetworkID: network_id,
              Sequence: sequence
            };
            // auto fee calculations and submit
            feeResponse = await client.send({ command: 'fee' });
            if ( Number(feeResponse.drops.open_ledger_fee) > feeStartAmount && Number(feeResponse.drops.open_ledger_fee) > Number(feeResponse.drops.base_fee) && auto_adjust_fee == true ) { feeAmount = ( Number(feeResponse.drops.open_ledger_fee) + Number(fee_adjust_amount) ).toString() } else { feeAmount = feeResponse.drops.base_fee };
            if ( auto_adjust_fee == true && Number(feeAmount) < fee_max_amount ){            
              tokenTx["Fee"] = feeAmount;
              const { signedTransaction: tokenTxSigned } = lib.sign(tokenTx, keypair);
              var { engine_result: tokenResult } = await client.send({ command: 'submit', 'tx_blob': tokenTxSigned });
              logVerbose(`\nfee auto adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} fee_open_ledger_fee:${feeResponse.drops.open_ledger_fee} fee_base_fee:${feeResponse.drops.base_fee}`);
            } else {
              if ( auto_adjust_fee == true ) { consoleLog(`${YW}maxfee limit reached, swapping to waiting for ledger end for fee calculations${CL}`) };
              networkInfo = await lib.utils.txNetworkAndAccountValues(xahaud, sourceAccount);
              tokenTx = { ...tokenTx, ...networkInfo.txValues };
              var { response: { engine_result: tokenResult } } = await lib.signAndSubmit(tokenTx, xahaud, keypair);
              logVerbose(`\nfee NO adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} fee_open_ledger_fee:${feeResponse.drops.open_ledger_fee} fee_base_fee:${feeResponse.drops.base_fee}`);
            }

            if ( tokenResult !== "tesSUCCESS" && tokenResult !== "terQUEUED") { 
              tesSUCCESS = false;
              consoleLog(`${RD}${evrAmount} EVR FAILED TO SEND, ${sourceAccount} xxx ${account} (fee:${tokenTx.Fee}), result: ${tokenResult}${CL}`);
            } else {
              consoleLog(`${GN}${evrAmount} EVR sent, ${sourceAccount} --> ${account} (fee:${tokenTx.Fee}), result: ${tokenResult}${CL}`);
            }
          }
        }

        // Set regularKey
        if (set_regular_key && tesSUCCESS){
          const { account_data: { Sequence: sequence } } = await client.send({ command: "account_info", account: account });
          let regularTx = {
            TransactionType: 'SetRegularKey',
            Account: account,
            RegularKey: sourceAccount,
            NetworkID: network_id,
            Sequence: sequence
          };
          // auto fee calculations and submit
          feeResponse = await client.send({ command: 'fee' });
          if ( Number(feeResponse.drops.open_ledger_fee) > feeStartAmount && Number(feeResponse.drops.open_ledger_fee) > Number(feeResponse.drops.base_fee) && auto_adjust_fee == true ) { feeAmount = ( Number(feeResponse.drops.open_ledger_fee) + Number(fee_adjust_amount) ).toString() } else { feeAmount = feeResponse.drops.base_fee };
          if ( auto_adjust_fee == true && Number(feeAmount) < fee_max_amount ){            
            regularTx["Fee"] = feeAmount;
            try {
              var regularKeypair = lib.derive.familySeed(allAccount_seeds[loop]);
            } catch (err) {
              console.error(`Error reading secret for account ${loop} : ${account}`);
              logVerbose("error returned ->" + err)
            }
            const { signedTransaction: regularTxSigned } = lib.sign(regularTx, regularKeypair);
            var { engine_result: regularResult } = await client.send({ command: 'submit', 'tx_blob': regularTxSigned });
            logVerbose(`\nfee auto adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} fee_open_ledger_fee:${feeResponse.drops.open_ledger_fee} fee_base_fee:${feeResponse.drops.base_fee}`);
          } else {
            if ( auto_adjust_fee == true ) { consoleLog(`${YW}maxfee limit reached, swapping to waiting for ledger end for fee calculations${CL}`) };
            networkInfo = await lib.utils.txNetworkAndAccountValues(xahaud, account);
            regularTx = { ...regularTx, ...networkInfo.txValues };
            try {
              var regularKeypair = lib.derive.familySeed(allAccount_seeds[loop]);
            } catch (err) {
              console.error(`Error reading secret for account ${loop} : ${account}`);
              logVerbose("error returned ->" + err)
            }
            var { response: { engine_result: regularResult } } = await lib.signAndSubmit(regularTx, xahaud, regularKeypair);
            logVerbose(`\nfee NO adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} fee_open_ledger_fee:${feeResponse.drops.open_ledger_fee} fee_base_fee:${feeResponse.drops.base_fee}`);
          }

          if ( regularResult !== "tesSUCCESS" && regularResult !== "terQUEUED" ) { 
            tesSUCCESS = false;
            consoleLog(`${RD}regular key ${sourceAccount} FAILED TO BE SET on ${account} (fee:${regularTx.Fee}), result: ${regularResult}${CL}`);
          } else {
            consoleLog(`${GN}regular key ${sourceAccount} set on ${account} (fee:${regularTx.Fee}), result: ${regularResult}${CL}`);
          }
        }

        if ( tesSUCCESS == true ) {
          break 
        } else {
          if ( attempt > 2 ) {
            consoleLog(`${RD}something failed again, reached max retries, exiting...${CL}`);
            process.exit()
          };
          consoleLog(`${RD}something failed, retying, ${attempt} of 2${CL}`);
          attempt++;
          tesSUCCESS = true;
        };
      }
    } else {
      consoleLog(`${YW}skipping ${account} as its the source account.${CL}`);
    };
    consoleLog(" ");
    consoleLog(" ---------------- ");
    loop++;
  };
  console.log(" ");
  consoleLog(" ---------------- ");
  if (tesSUCCESS){
    await updateEnv('sourceAccount', accounts[0]);
    await updateEnv('evrDestinationAccount', accounts[0]);
    await updateEnv('secret', account_seeds[0]);
    let saveAccounts = accounts.slice(1);
    await updateEnv('accounts', saveAccounts.join('\n'));
    if (reputationAccounts.length != "0" ) { await updateEnv('reputationAccounts', reputationAccounts.join('\n')) };
    consoleLog(`${GN}all accounts succesfully checked and setup, and details exported to .env file${CL}`)
    consoleLog(" ---------------- ");
    consoleLog(" ");
    return 0
  } else {
    consoleLog(`${RD}there was a fault in querying 1 or more accounts, scroll up to find out more, NOT exporting details to .env file${CL}`)
    consoleLog(" ---------------- ");
    consoleLog(" ");
    return 1
  };
};

//...............................................................................................................................................................................................
// monitor_claimreward  .........................................................................................................................................................................

async function monitor_claimreward(){
  console.log(" ---------------- ");
  consoleLog("Starting the monitor claim rewards module...");

  var liveDefinitions = await client.send({ "command": "server_definitions" });
  var definitions = new lib.XrplDefinitions(liveDefinitions);
  var total_reward_accumulated = 0;
  var tesSUCCESS = true;

  // onchain reward rate calculation
  let rewardRate = await client.send({
    command: 'ledger_entry',
    hook_state: {
      account: 'rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh',
      key: '0000000000000000000000000000000000000000000000000000000000005252', // RR
      namespace_id: '0000000000000000000000000000000000000000000000000000000000000000'
    }
  })
  let rewardDelay = await client.send({
    command: 'ledger_entry',
    hook_state: {
      account: 'rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh',
      key: '0000000000000000000000000000000000000000000000000000000000005244', // RD
      namespace_id: '0000000000000000000000000000000000000000000000000000000000000000'
    }
  })
  rewardRate = await hookStateXLFtoBigNumber(rewardRate.node['HookStateData']);
  rewardDelay = await hookStateXLFtoBigNumber(rewardDelay.node['HookStateData']);
  rewardRateHuman = await calcrewardRateHuman(rewardRate);
  rewardDelayHuman = await calcrewardDelayHuman(rewardDelay);

  consoleLog(`${YW}Current Ledger rewardrate --->${rewardRateHuman}  rewardDelay --->${rewardDelayHuman}${CL}`);
  consoleLog(" ---------------- ");
  consoleLog(" ");

  if (reputationAccounts.length != 0 ) {
    var allAccounts = accounts.concat(reputationAccounts);
  } else {
    consoleLog("no reputation accounts to check")
    var allAccounts = accounts;
  }
  consoleLog("checking XAH levels on all " + accounts.length + " accounts and " + reputationAccounts.length + " reputation accounts, with total amount of " + allAccounts.length + " to check...");
  logVerbose(`allAccounts --> ${allAccounts}`);

  for (const account of allAccounts) {
    consoleLog("starting check on account " + account);

    try {
      var { account_data } = await client.send({ command: "account_info", account })
      var { ledger } = await client.send({ command: 'ledger', ledger_index: 'validated' })
    } catch (err){
      console.error(`Error getting account info, has account(${account}) been activated yet? is ${network} the correct network?`);
      logVerbose("error returned ->" + err);
      tesSUCCESS = false;
      continue
    }

    logVerbose("\naccount_data -- >" + JSON.stringify(account_data) + "\n\nledger -->" + JSON.stringify(ledger) + "\n");

    const RewardLgrFirst = account_data?.RewardLgrFirst || 0;
    const RewardLgrLast = account_data?.RewardLgrLast || 0;
    const RewardTime = account_data?.RewardTime || 0;
    const RewardAccumulator = account_data?.RewardAccumulator ? parseFloat(BigInt('0x' + account_data?.RewardAccumulator).toString()) : 0;
    const remaining_sec = rewardDelay - (ledger.close_time - RewardTime);
    const uninitialized = account_data?.RewardLgrFirst === undefined;
    const claimable = remaining_sec <= 0;
    const now = new Date();
    const claimableDate = new Date(now.getTime() + remaining_sec * 1000);
    const claimableTime = await calcrewardDelayHuman(remaining_sec);

    // calculate account reward
    const cur = Number(ledger.ledger_index);
    const elapsed = cur - RewardLgrFirst;
    const elapsed_since_last = cur - RewardLgrLast;
    let accumulator = RewardAccumulator;
    if (account_data && parseFloat(account_data?.Balance) > 0 && elapsed_since_last > 0) {
      accumulator += parseFloat(account_data?.Balance) / 1000000 * elapsed_since_last;
    }
    const reward = accumulator / elapsed * rewardRate;

    logVerbose(`RewardLgrFirst.${RewardLgrFirst}  RewardLgrLast.${RewardLgrLast}  RewardTime.${RewardTime}  RewardAccumulator.${RewardAccumulator}  rewardRate.${rewardRate} rewardDelay.${rewardDelay} remaining_sec.${remaining_sec}  claimableTime.${claimableTime}  uninitialized.${uninitialized}  claimable.${claimable}  claimableDate.${claimableDate}  reward.${reward}`)
    
    if (uninitialized) {
      consoleLog(`${YW}account found to be Uninitialized, registering for claim rewards now...${CL}`);

      const { account_data: { Sequence: sequence } } = await client.send({ command: "account_info", account: account });
      var claimTx = {
        Account: account,
        TransactionType: 'ClaimReward',
        Issuer: 'rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh',
        NetworkID: network_id,
        Sequence: sequence,
        Fee: "0",
        SigningPubKey: "",
      };

      // auto fee calculations and submit
      const encoded = await lib.binary.encode(claimTx, definitions);
      feeResponse = await client.send({ command: 'fee', tx_blob: encoded });

      if ( Number(feeResponse.drops.open_ledger_fee) > feeStartAmount && Number(feeResponse.drops.open_ledger_fee) > Number(feeResponse.drops.base_fee) && auto_adjust_fee == true ) { feeAmount = ( Number(feeResponse.drops.open_ledger_fee) + Number(fee_adjust_amount) ).toString() } else { feeAmount = feeResponse.drops.base_fee };
      if ( auto_adjust_fee == true && Number(feeAmount) < fee_max_amount ){
        claimTx["Fee"] = feeAmount;
        const { signedTransaction: claimTxSigned } = lib.sign(claimTx, keypair, definitions);
        var { engine_result: claimTxResult } = await client.send({ command: 'submit', 'tx_blob': claimTxSigned });
        logVerbose(`\nfee auto adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} fee_open_ledger_fee:${feeResponse.drops.open_ledger_fee} fee_base_fee:${feeResponse.drops.base_fee}`);
      } else {
        if ( auto_adjust_fee == true ) { consoleLog(`${YW}maxfee limit reached, swopping to waiting for ledger end for fee calculations${CL}`) };
        networkInfo = await lib.utils.txNetworkAndAccountValues(xahaud, account);
        claimTx = { ...claimTx, ...networkInfo.txValues };
        var { response: { engine_result: claimTxResult } } = await lib.signAndSubmit(claimTx, xahaud, keypair);
        logVerbose(`\nfee no adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} feeResponse:${feeResponse.drops.open_ledger_fee}`);
      }

      if ( claimTxResult !== "tesSUCCESS" && claimTxResult !== "terQUEUED") { 
        tesSUCCESS = false;
        consoleLog(`${RD}Registration failed (fee:${claimTx.Fee}), result: ${claimTxResult}${CL}`);
      } else {
        consoleLog(`${GN}Registration sucessfully initialized for ${account}${CL}`);
      }
      consoleLog(" ---------------- ");
      consoleLog(" ");
      continue
    }

    if (claimable) {
      consoleLog(`${GN}account is within a claimable timeframe, rewards will be ${reward} XAH, now attempting a claim...${CL}`);

      const { account_data: { Sequence: sequence } } = await client.send({ command: "account_info", account: account });
      var claimTx = {
        Account: account,
        TransactionType: 'ClaimReward',
        Issuer: 'rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh',
        NetworkID: network_id,
        Sequence: sequence,
        Fee: "0",
        SigningPubKey: "",
      };
      const encoded = await lib.binary.encode(claimTx, definitions);
      feeResponse = await client.send({ command: 'fee', tx_blob: encoded });

      // auto fee calculations and submit
      if ( Number(feeResponse.drops.open_ledger_fee) > feeStartAmount && Number(feeResponse.drops.open_ledger_fee) > Number(feeResponse.drops.base_fee) && auto_adjust_fee == true ) { feeAmount = ( Number(feeResponse.drops.open_ledger_fee) + Number(fee_adjust_amount) ).toString() } else { feeAmount = feeResponse.drops.base_fee };
      if ( auto_adjust_fee == true && Number(feeAmount) < fee_max_amount ){
        claimTx["Fee"] = feeAmount;
        const { signedTransaction: claimTxSigned } = lib.sign(claimTx, keypair, definitions);
        var { engine_result: claimTxResult } = await client.send({ command: 'submit', 'tx_blob': claimTxSigned });
        logVerbose(`\nfee auto adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} fee_open_ledger_fee:${feeResponse.drops.open_ledger_fee} fee_base_fee:${feeResponse.drops.base_fee}`);
      } else {
        if ( auto_adjust_fee == true ) { consoleLog(`${YW}maxfee limit reached, swopping to waiting for ledger end for fee calculations${CL}`) };
        networkInfo = await lib.utils.txNetworkAndAccountValues(xahaud, account);
        claimTx = { ...claimTx, ...networkInfo.txValues };
        var { response: { engine_result: claimTxResult } } = await lib.signAndSubmit(claimTx, xahaud, keypair);
        logVerbose(`\nfee no adjust --> feeStartAmount:${feeStartAmount} feeAmount:${feeAmount} fee_max_amount:${fee_max_amount} fee_open_ledger_fee:${feeResponse.drops.open_ledger_fee} fee_base_fee:${feeResponse.drops.base_fee}`);
      }


      if ( claimTxResult !== "tesSUCCESS" && claimTxResult !== "terQUEUED") {
        tesSUCCESS = false;
        consoleLog(`${RD}claim failed for ${account} (fee:${claimTx.Fee}), result: ${claimTxResult}${CL}`);
      } else {
        consoleLog(`${GN}claim success, re-claimed ${reward} XAH${CL}`);
        total_reward_accumulated += reward;
      }
    } else {
      consoleLog(`${YW}account is not within a claimable timeframe, next claimable date is in ${claimableTime}${CL}, accumulated rewards so far ${reward} XAH`)
    }

    consoleLog(" ---------------- ");
    consoleLog(" ");
  };
  if (tesSUCCESS){
    consoleLog(`${GN}all accounts succesfully checked, total accumulated rewards are ${total_reward_accumulated} XAH${CL}`)
    consoleLog(" ---------------- ");
    consoleLog(" ");
    return 0
  } else {
    consoleLog(`${RD}there was a fault in querying 1 or more accounts, scroll up to find out more, total accumulated rewards this cycle ${total_reward_accumulated} XAH${CL}`)
    consoleLog(" ---------------- ");
    consoleLog(" ");
    return 1
  };
};

//...................................................................................................................................................................................................
// support functions     ............................................................................................................................................................................

// fetch account EVR balance ........................................................................................................................................................................
async function GetEvrBalance(account){
  logVerbose("fetching the EVR balance for " + account);
  let marker = ''
  let l = []
  let balance = 0
  let balanceTrunc = 0
  while (typeof marker === 'string') {
    const lines = await client.send({ command: 'account_lines', account, marker: marker === '' ? undefined : marker })

    marker = lines?.marker === marker ? null : lines?.marker
    logVerbose(`trustlines found :${lines?.lines?.length}`)
    lines?.lines?.forEach(token => {
      if (token.currency == "EVR" && token.account == trustlineAddress) {
        balanceTrunc = Math.trunc(token.balance * 10000) / 10000; // force truncation of number, to prevent large number which fails due to tecPATH_PARTIAL
        balance = Number(balance) + Number(balanceTrunc);
        logVerbose(`found matching trustline of ${trustlineAddress} with balance of ${balance}, full reply -> ${JSON.stringify(token)}`)
        return isNaN(Number(balance)) ? 0 : Number(balance);
      }
    })
  }
  return isNaN(Number(balance)) ? 0 : Number(balance);
}

// .env file handling  ........................................................................................................................................................................
async function updateEnv(key, value) {
  const envPath = path.resolve(__dirname, '.env');

  try {
    let envFileContent = await fs.promises.readFile(envPath, 'utf8');

    // regular expression to match the key (handles cases with or without spaces around '=', and new lines within accounts)
    const regex = new RegExp(`^\\s*${key}\\s*=\\s*(?:"[^"]*"|[^\\n]*)$`, 'm');

    // Replace the key-value pair if found
    if (regex.test(envFileContent)) {
      envFileContent = envFileContent.replace(regex, `${key}="${value}"`);
    } else {
      // If key is not found, append it at the end
      envFileContent += `\n${key}="${value}"\n`;
    }
    logVerbose(`Updating ${key} to ${value} in .env`);
    await fs.promises.writeFile(envPath, envFileContent, 'utf8');

    // Reload the environment variables to reflect the change
    dotenv.config();

    //logVerbose(`Updated ${key} to ${value} in .env successfully`);
  } catch (err) {
    console.error('Error updating .env file:', err);
  }
}

// claim reward functions .............................................
function get_exponent(xfl) {
  if (xfl < 0n)
    throw new Error("Invalid XFL");
  if (xfl == 0n)
    return 0n;
  return ((xfl >> 54n) & 0xFFn) - 97n;
};

function get_mantissa(xfl) {
  if (xfl < 0n)
    throw new Error("Invalid XFL");
  if (xfl == 0n)
    return 0n;
  return xfl - ((xfl >> 54n) << 54n);
};

function is_negative(xfl) {
  if (xfl < 0n)
    throw new Error("Invalid XFL");
  if (xfl == 0n)
    return false;
  return ((xfl >> 62n) & 1n) == 0n;
};

function to_string(xfl) {
  if (xfl < 0n)
    throw new Error("Invalid XFL");
  if (xfl == 0n)
    return "<zero>";
  return (is_negative(xfl) ? "-" : "+") +
    get_mantissa(xfl).toString() + "E" + get_exponent(xfl).toString();
};

function xflToFloat(xfl) {
  return parseFloat(to_string(xfl));
};

function changeEndianness(str){
  const result = [];
  let len = str.length - 2;
  while (len >= 0) {
    result.push(str.substr(len, 2));
    len -= 2;
  }
  return result.join('');
};

function hookStateXLFtoBigNumber(stateData) {
  const data = changeEndianness(stateData);
  const bi = BigInt('0x' + data);
  return xflToFloat(bi);
};

function calcrewardRateHuman(rewardRate) {
  if (!rewardRate) return "0 %";
  if (rewardRate < 0 || rewardRate > 1) return "Invalid rate";
  return (Math.round((((1 + rewardRate) ** 12) - 1) * 10000) / 100) + " %";
};

function calcrewardDelayHuman(rewardDelay) {
  if (rewardDelay / 3600 < 1) return Math.ceil(rewardDelay / 60) + " mins";
  if (rewardDelay / (3600 * 24) < 1) return Math.ceil(rewardDelay / 3600) + " hours";
  return Math.ceil(rewardDelay / (3600 * 24)) + ' days';
};

//........................................................................................................................................................................................
// start sections ........................................................................................................................................................................

async function validate() {
  await getAccounts();
  if (!accounts || accounts.length == 0 || accounts[0] == "") {
    consoleLog("no accounts set");
    return false;
  }
  if (!keypair && (run_transfer_funds || run_monitor_balance)) {
    consoleLog("no secret/seed/keypair set")
    return false;
  }
  return true;
}

const main = async () => {
  if (run_wallet_setup) { use_keypair_file = true };
  
  const valid = await validate();
  if (valid) {
    if (run_monitor_claimreward) { await monitor_claimreward() };
    if (run_transfer_funds) { await transfer_funds() };
    if (run_monitor_balance) { await monitor_balance() };
    if (run_monitor_heartbeat) { await monitor_heartbeat() };
  }
};

// check if theres any command line arguments used
async function start(){
  await networkSetup();
  if (command) {
    const valid = await validate();
    if (valid) {
      switch (command) {
        case 'wallet_setup':
              await wallet_setup();
              break;
        case 'transfer_funds':
              await transfer_funds();
              break;
        case 'monitor_balance':
              await monitor_balance();
              break;
        case 'monitor_heartbeat':
              await monitor_heartbeat();
              break;
        case 'monitor_claimreward':
              await monitor_claimreward();
              break;
        default:
            console.log(`Unknown command: ${command}`);
            console.log('Usage: node evernode_monitor.js <command>');
            console.log('Commands available are:');
            console.log('  wallet_setup  - setup wallets in key_pair.txt file ready to deploy evernodes');
            console.log('  transfer_funds  - sweep funds (EVR/XAH) to chosen account');
            console.log('  monitor_balance  - Check balance (EVR/XAH), and top up if needed');
            console.log('  monitor_heartbeat  - Check for recent heartbeat, and email failures');
            console.log('  monitor_claimreward  - Check the balance adjustment hook, and claim rewards');
            break;
      };
    ;}
  } else {
    await main();
  };
  client.close();
  // Workaround so all queued emails are sent. 
  // I had to explicitly call the exit() function as the application was not stopping 
  // in case of Xahaud request failure, I don't know why. 
  if (email_notification) {
    consoleLog('waiting for mail to send, before exiting..'); 
    setTimeout(function () {
    exit();
    }, 10000);
  } else {
    consoleLog('all finished...');
  }
};
start();