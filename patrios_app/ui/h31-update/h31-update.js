
// function InitPage() {    
// }

// Set up the form for uploads
document.getElementById("form").addEventListener("submit", InputHandler);
// Set up the drop box
document.getElementById("the-box").addEventListener("drop", DropHandler);
document.getElementById("the-box").addEventListener("dragover", DragHandler);
// Set up selection of file
document.getElementById("file").onchange = InputHandler;

function InputHandler(event){
    event.preventDefault();
    pop();
    const file = document.getElementById("file").files[0];
    UploadFiles(file);
}

function DropHandler(event) {
    event.preventDefault();
    pop();
    const file = event.dataTransfer.files[0];
    UploadFiles(file);
}

function DragHandler(event) {
    event.preventDefault();
}

var modal = null;
function pop() {
    if(modal === null){
        document.getElementById("popupBox").style.display = "block";
        modal = true;
    }
    else{
        document.getElementById("popupBox").style.display = "none";
        modal = null;
    }
}

function UploadFiles(file) {
    const progress = document.getElementById("fileprogress");
    progress.hidden = false;
    progress.value = 0;
    progress.max = file.size;
    const query = window.btoa(JSON.stringify({
        binary: "raw",
        "flow-control": true,
        payload: "fsreplace1",
        path: "/tmp/" + file.name,
        superuser: "require"
    }));

    // Opens a "channel" to cockpit in order to start writing file
    const ws = new WebSocket("wss://" + window.location.host + 
       	"/cockpit/channel/" + cockpit.transport.csrf_token + "?" + query);
    ws.onopen = function() {
        ws.binaryType = "arraybuffer";
        const reader = file.stream().getReader();
        let wssent = 0;
        reader.read().then(async function sendfile({ done, value }) {
            if(done) {
                ws.close(1000);
                while(ws.bufferedAmount > 0) {
                    progress.value = wssent - ws.bufferedAmount;
                    await sleep(50);
                }
                progress.value = wssent;
                return
            }

            /* Send Chunks of max 64k */
            const batch = 64 * 1024;
            const minbuf = 5 * 1024 * 1024;
            const maxbuf = 10 * 1024 * 1024;
            const len = value.byteLength;
            for (let i = 0; i < len; i += batch) {
                if (ws.bufferedAmount > maxbuf){
                    while (ws.bufferedAmount > minbuf) {
                        await sleep(50);
                    }
                }
                const n = Math.min(len, i + batch);
                ws.send(value.subarray(i, n));
                wssent += n-i;
                progress.value = wssent - ws.bufferedAmount;
            }
            return reader.read().then(sendfile);
        });
    };

    ws.onerror = function(error) {
        console.log(error);
    };

    ws.onmessage = function(ev) {
        console.log(ev);
    };
    
    ws.onclose = function(ev) {
        console.log(ev);
        document.getElementById("form").reset();
        pop();
        if (ev.code == 1000) {
            alert("Upload Successful");
            document.getElementById("outputText").value += "Finished Upload. Starting Update..." + "\n";
        }
        Update(file.name);
    };
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function Update(name) {
    installProcess = cockpit.spawn(["mender", "-install", "/tmp/" + name], { superuser : "try" });
    installProcess.stream(outputData => {
        document.getElementById("outputText").value += "\n";
        document.getElementById("outputText").value += outputData;
        document.getElementById("outputText").value += "\n";
        console.log(outputData);
    });
    // After
    installProcess.then(lastData => {
        document.getElementById("outputText").value += "\n" + lastData.message + "\n";
        CommitFunc();
    });
    installProcess.catch(error => {
        document.getElementById("outputText").value += "\n" + "Error While Updating : " + "\n";
        document.getElementById("outputText").value += "Message : " + error.message + "\n";
        document.getElementById("outputText").value += "Problem Code : " + error.problem + "\n";
        document.getElementById("outputText").value += "Exit Status : " + error.exit_status + "\n";
        document.getElementById("outputText").value += "Exit Signal : " + error.exit_signal + "\n";
    });
    
}

function CommitFunc() {
    commitProcess = cockpit.spawn(["mender", "-commit"], { superuser : "try" });
    commitProcess.stream(outputData => {
        document.getElementById("outputText").value += "\n";
        document.getElementById("outputText").value += outputData;
        document.getElementById("outputText").value += "\n";
    });
    commitProcess.then(lastData => {
        document.getElementById("outputText").value += "\n" + "Rebooting Now..." + "\n"
        Reboot();
    });
    commitProcess.catch(error => {
        document.getElementById("outputText").value += "\n" + "Error While Commiting : " + "\n";
        document.getElementById("outputText").value += "Message : " + error.message + "\n";
        document.getElementById("outputText").value += "Problem Code : " + error.problem + "\n";
        document.getElementById("outputText").value += "Exit Status : " + error.exit_status + "\n";
        document.getElementById("outputText").value += "Exit Signal : " + error.exit_signal + "\n";
    });
}

function Reboot() {
    cockpit.spawn(["reboot", "now"]);
}


// Send a 'init' message.  This tells integration tests that we are ready to go
cockpit.transport.wait(function() { });
