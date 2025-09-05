
const request = require('supertest');
const express = require('express');

// Mock the auth-server module
const app = express();
app.get('/auth', (req, res) => {
    res.status(200).send('OK');
});

describe('GET /auth', () => {
    it('responds with 200 OK', async () => {
        const response = await request(app).get('/auth');
        expect(response.statusCode).toBe(200);
        expect(response.text).toBe('OK');
    });
});
