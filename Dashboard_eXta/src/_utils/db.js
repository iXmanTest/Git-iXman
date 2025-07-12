require('dotenv').config();
const sql = require('mssql');

const config = {
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    server: process.env.DB_SERVER,
    database: process.env.DB_DATABASE,
    options: {
        encrypt: false,
        enableArithAbort: true,
        trustServerCertificate: true,
        connectionTimeout: 30000,
        requestTimeout: 30000,
        packetSize: 16384,
        keepAlive: true,
        keepAliveInterval: 60000,
    },
    port: 1433,
};


async function connectWithRetry() {
    let retries = 5;
    while (retries) {
        try {
            await sql.connect(config);
            console.log('Connected to the database');
            break;
        } catch (err) {
            console.error('Connection failed, retrying...', err);
            retries -= 1;
            await new Promise((res) => setTimeout(res, 5000));
        }
    }
    if (!retries) {
        console.error('Could not connect to the database after multiple attempts');
    }
}

connectWithRetry();

async function executeQuery(query, params = []) {
    try {
        let pool = await sql.connect(config);
        let request = pool.request();
        params.forEach((param) => {
            request.input(param.name, param.type, param.value);
        });
        let result = await request.query(query);
        return result.recordset || [];
    } catch (err) {
        console.error('SQL error', err);
        throw err;
    }
}

module.exports = { executeQuery };