require("dotenv").config(); // MUST be first line

const express = require("express");
const pool = require("./src/db"); // <-- path changed

const app = express();
const PORT = 3000;

app.use(express.json());

app.get("/api/health", async (req, res) => {
  try {
    const result = await pool.query("SELECT NOW() as now");
    res.json({ ok: true, dbTime: result.rows[0].now });
  } catch (err) {
    console.error("DB ERROR:", err);
    res.status(500).json({
      ok: false,
      error: err.message,
      code: err.code,
    });
  }
});

app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
});
