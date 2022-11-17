const express = require('express');
const fetch = require('isomorphic-fetch');
const config = require('./config');

if (config.aicstring){ 
    appInsights.setup(config.aicstring)
    .setAutoDependencyCorrelation(true)
    .setAutoCollectRequests(true)
    .setAutoCollectPerformance(true, true)
    .setAutoCollectExceptions(true)
    .setAutoCollectDependencies(true)
    .setAutoCollectConsole(true)
    .setUseDiskRetryCaching(true)
    .setSendLiveMetrics(true)
    .setDistributedTracingMode(appInsights.DistributedTracingModes.AI_AND_W3C);
    appInsights.defaultClient.context.tags[appInsights.defaultClient.context.keys.cloudRole] = "calc-explorer";
    appInsights.start();
    appInsights.defaultClient.commonProperties = {
        slot: config.version
    };
}

const OS = require('os');
const e = require('express');
const app = express();
app.use(express.json())

var publicDir = require('path').join(__dirname, '/public');
app.use(express.static(publicDir));

var startDate = new Date();

app.get('/ready/:seconds', function(req, res) {
    const seconds = req.params.seconds;
    var waitTill = new Date(startDate.getTime() + seconds * 1000);
    if(waitTill > new Date()){
        console.log("Not ready yet");
        res.status(503).send('Not ready yet');
    }
    else
    {   console.log("Ready");
        res.send('Yes, I am ready');
    }    
});

app.get('/healthz', function(req, res) {
    const data = {
        uptime: process.uptime(),
        message: 'Ok',
        date: new Date()
      }
    res.status(200).send(data);
});

app.get('/ping', function(req, res) {
    console.log('received ping GET');
    var sourceIp = req.connection.remoteAddress;
    var forwardedFrom = (req.headers['x-forwarded-for'] || '').split(',').pop();
    var pong = { response: "pong!", host: OS.hostname(), source: sourceIp, forwarded: forwardedFrom, version: config.version };
    console.log(pong);
    res.send(pong);
});

app.post('/ping', function(req, res) {
    console.log('received ping POST');
    var sourceIp = req.connection.remoteAddress;
    var forwardedFrom = (req.headers['x-forwarded-for'] || '').split(',').pop();
    var pong = { response: "pong!", host: OS.hostname(), source: sourceIp, forwarded: forwardedFrom, version: config.version };
    console.log(pong);
    res.send(pong);
});

// curl -X POST http://localhost:3000/api/calculate -H "Content-Type: application/json"  -d '{ "url": "http://10.0.1.4:8080/ip" }'
app.post('/api/calculate', function(req, res) {
    console.log('received calcuation POST');
    console.log('Got body:', req.body);
    console.log('Got headers:', req.headers);
    var endDate = new Date();
    var sourceIp = req.connection.remoteAddress;
    var forwardedFrom = (req.headers['x-forwarded-for'] || '').split(',').pop();
    var pong = { timestamp: endDate, value: "[ b, u, g]", error: "looks like a 19 bug", host: OS.hostname(), remote: sourceIp };
    console.log(pong);
    res.send(pong);
});

app.post('/', (req, res) => {
    console.log('Got body:', req.body);

    var url;
    if (req.body.isdaprinvoke)
    {
        url = "http://localhost:" + process.env.DAPR_HTTP_PORT + "/v1.0/invoke/" + req.body.url;
        console.log("using dapr invoking " + url);
    }
    else
    {
        url = req.body.url;
        console.log("using url " + url);
    }

    fetch(url, {
        method: req.body.action,
        headers: {
            "Content-Type": "application/json"
        }
    }).then((response) => {
        if (!response.ok) {
            console.log("Failed to call");
            res.sendStatus(response.status);
        }
        // var text =
        return response.json();        
    }).then((text) => {
        console.log(text);
        res.status(200).send(text);
    }).catch((error) => {
        console.log("failed to call " + url);
        console.log(error);
        res.status(500).send({message: error});
    });
}); 

// curl -X POST http://127.0.0.1:3000  -F 'url=https://ipinfo.io/json' -F 'action=GET' 
// curl -X POST https://x.azurecontainerapps.io -H "Content-Type: application/json"  -d '{ "url": "http://10.0.1.4:8080/ip" }'

console.log(config);
console.log(OS.hostname());
app.listen(config.port);
console.log('Listening on localhost:'+ config.port);
var launchTime = performance.now();
console.log("Started at " + launchTime);