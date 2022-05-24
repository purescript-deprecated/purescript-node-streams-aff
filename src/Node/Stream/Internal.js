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
  // // https://github.com/nodejs/node/issues/6456
  // return () => {
  // 	s && s.isTTY && s._handle && s._handle.setBlocking && s._handle.setBlocking(true);
  // };

  // https://github.com/nodejs/node/issues/6379#issuecomment-1064044886
  return () => {
  	// s && s._handle && s._handle.setBlocking && s._handle.setBlocking(true);
  	s._handle.setBlocking(true);
  };
}