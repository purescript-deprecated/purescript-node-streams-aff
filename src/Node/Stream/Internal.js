export function onceReadable(s) {
  return f => () => {
    s.once("readable", f);
  };
}

export function readableEnded(s) {
	return () => {
		return s.readableEnded;
	};
}