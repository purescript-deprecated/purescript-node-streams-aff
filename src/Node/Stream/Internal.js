import timers from 'node:timers';

export function onceReadable(s) {
  return f => () => {
    s.once('readable', f);
  };
}

export function onceEnd(s) {
  return f => () => {
    s.once('end', f);
  };
}

export function onceDrain(s) {
  return f => () => {
    s.once('drain', f);
  };
}

export function onceError(s) {
  return f => () => {
    s.once('error', f);
  };
}

export function unbuffer(s) {
  // https://github.com/nodejs/node/issues/6456
  // https://github.com/nodejs/node/issues/6379#issuecomment-1064044886
  // https://nodejs.org/api/process.html#a-note-on-process-io
  //
  // Maybe the stream promise API doesn't have this problem?
  // https://github.com/sparksuite/waterfall-cli/issues/258
  return () => {
  	s._handle.setBlocking(true);
  };
}

export function setInterval(t) {
  return f => () => {
    return timers.setInterval(f, t);
  }
}

export function clearInterval(timeout) {
  return () => {
    timers.clearInterval(timeout);
  }
}

export function hasRef(timeout) {
  return () => {
    return timeout.hasRef();
  }
}