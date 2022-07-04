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

export const onceError = s => f => () => {
  s.once('error', error => f(error)());
  return () => {s.removeListener('error', f);};
}

export const readable = s => () => {
  return s.readable;
}

export const push = s => buf => () => {
  return s.push(buf);
}

export const newReadable = () => {
  return new stream.Readable();
}