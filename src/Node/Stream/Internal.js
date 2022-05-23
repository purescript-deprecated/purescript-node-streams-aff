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