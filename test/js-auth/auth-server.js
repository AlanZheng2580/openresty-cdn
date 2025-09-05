const express = require('express');
const app = express();

app.get('/auth', (req, res) => {
    console.log('--- New Request ---');
    console.log('Date.now(): ', Date.now())
    console.log('Original URL: ', req.originalUrl);
    console.log('Method: ', req.method);
    console.log('Query Parameters: ', req.query);
    console.log('Headers : ', req.headers);
    
    if (req.body && Object.keys(req.body).lenght > 0) {
        console.log('Body: ', req.body);
    }

    res.status(200).send('OK');
});

const PORT = 2345
app.listen(PORT, () => {
    console.log(`Auth server listening on port ${PORT}`)
})