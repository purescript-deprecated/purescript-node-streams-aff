import timers from 'node:timers';

export function onceReadable(s) {
  return f => () => {
    s.once('readable', f);
    return () => {s.removeListener('readable', f);};
  };
}

export function onceEnd(s) {
  return f => () => {
    s.once('end', f);
    return () => {s.removeListener('end', f);};
  };
}

export function onceDrain(s) {
  return f => () => {
    s.once('drain', f);
    return () => {s.removeListener('drain', f);};
  };
}

export function onceError(s) {
  return f => () => {
    s.once('error', f);
    return () => {s.removeListener('error', f);};
  };
}
