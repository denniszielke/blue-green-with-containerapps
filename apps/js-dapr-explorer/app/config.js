var config = {}

config.port = process.env.PORT || 3000;

config.version = "default - latest";

if (process.env.VERSION && process.env.VERSION.length > 0)
{
    console.log('found version environment variable');
    config.version = process.env.VERSION;
}
else {
    const fs = require('fs');
    if (fs.existsSync('version/info.txt')) {
    console.log('found version file');
    config.version = fs.readFileSync('version/info.txt', 'utf8');
    }
}

module.exports = config;