const express = require('express');
var bodyParser = require('body-parser');
const fetch = require('isomorphic-fetch');
const config = require('./config');
const OS = require('os');
const app = express();
  


var publicDir = require('path').join(__dirname, '/public');
app.use(express.static(publicDir));

// var urlencodedParser = bodyParser.urlencoded({ extended: false });
var jsonParser = bodyParser.json();

app.get('/healthz', function(req, res) {
    res.send('OK');
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


app.post('/', jsonParser, (req, res) => {
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