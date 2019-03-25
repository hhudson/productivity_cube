// IOTemp Agent Code

/* 
   Change Log
   2019-03-23
*/

/* GLOBALS and CONSTANTS -----------------------------------------------------*/

const ORDS_URL = "https://dev.insumlabs.com/webappsdev/hackathon2019/cube/state";


/* CLASS AND GLOBAL FUNCTION DEFINITIONS -------------------------------------*/

function postToCube(data,id) {
    
    
    // insert the schema retrieved above into the request url
    local url = ORDS_URL;
    //local headers = { "User-Agent" : "C2-Imp-Lib/0.1" };
    
    local headers = { "Content-Type": "application/json" };
    
    local requestData = { "deviceID": id, "side": data };
    local body = http.jsonencode(requestData);
    
    server.log(url);
    server.log(body);

    local response = http.post(url, headers, body).sendsync();
    
    if(response.statuscode != 201 && response.statuscode != 200) {
        server.log("error with http request, status: " + response.statuscode);
        server.log("error with http request: " + response.body);    
        return null;
    }

    //local JSONdata = http.jsondecode(response.body);
    
    server.log("Posted to Cube: "+data+", got return code: "+response.statuscode) ;
}



/* REGISTER DEVICE CALLBACKS  ------------------------------------------------*/

device.on("data", function(datapoint) {
    postToCube(datapoint.side, datapoint.id);    
});

/* REGISTER HTTP HANDLER -----------------------------------------------------*/

// This agent does not need an HTTP handler

/* RUNTIME BEGINS HERE -------------------------------------------------------*/

server.log("Cube Agent Running");
