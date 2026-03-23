const { spawn } = require('child_process');

const nextBin = require.resolve('next/dist/bin/next');
const child = spawn(process.execPath, [nextBin, 'dev', ...process.argv.slice(2)], {
  stdio: ['inherit', 'pipe', 'pipe'],
});

function stamp(line) {
  const now = new Date();
  const date = now.toISOString().slice(0, 19).replace('T', ' ');
  return `[${date}] ${line}`;
}

function pipeWithTimestamp(stream, target) {
  let buffer = '';
  stream.on('data', (chunk) => {
    buffer += chunk.toString();
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';
    for (const line of lines) {
      target.write(stamp(line) + '\n');
    }
  });

  stream.on('end', () => {
    if (buffer.length > 0) {
      target.write(stamp(buffer) + '\n');
      buffer = '';
    }
  });
}

pipeWithTimestamp(child.stdout, process.stdout);
pipeWithTimestamp(child.stderr, process.stderr);

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    child.kill(signal);
  });
}

child.on('exit', (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }

  process.exit(code || 0);
});
