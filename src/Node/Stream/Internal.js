import stream from 'stream';

export const onceReadable = s => f => () => {
  s.once('readable', f);
  return () => {s.removeListener('readable', f);};
}

export const onceEnd = s => f => () => {
  s.once('end', f);
  return () => {s.removeListener('end', f);};
}

export const onceDrain = s => f => () => {
  s.once('drain', f);
  return () => {s.removeListener('drain', f);};
}

// https://nodejs.org/api/events.html#emitteronceeventname-listener
export const onceError = s => f => () => {
  const listener = error => f(error)();
  s.once('error', listener);
  return () => {s.removeListener('error', listener);};
}

export const readable = s => () => {
  return s.readable;
}

export const writable = s => () => {
  return s.writable;
}

export const push = s => buf => () => {
  return s.push(buf);
}

export const newReadable = () => {
  return new stream.Readable();
}

export const newStreamPassThroughImpl = () => {
  return new stream.PassThrough();
}
