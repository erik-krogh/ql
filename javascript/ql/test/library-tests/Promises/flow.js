(async function () {
	var source = "source";
	
	var p1 = Promise.resolve(source);
	sink(await p1); // NOT OK
	
	var p2 = new Promise((resolve, reject) => resolve(source));
	sink(await p2); // NOT OK
	
	var p3 = new Promise((resolve, reject) => reject(source));
	sink(await p3); // OK!
	
	var p4 = new Promise((resolve, reject) => reject(source));
	try {
		var foo = await p4;
	} catch(e) {
		sink(e); // NOT OK!
	}
	
	Promise.resolve(source).then(x => sink(x)); // NOT OK!
	
	Promise.resolve(source).then(x => foo(x), y => sink(y)); // OK!
	
	new Promise((resolve, reject) => reject(source)).then(x => sink(x)); // OK!
	
	new Promise((resolve, reject) => reject(source)).then(x => foo(x), y => sink(y)); // NOT OK!
	
	Promise.resolve("foo").then(x => source).then(z => sink(z)); // NOT OK!
	
	Promise.resolve(source).then(x => "foo").then(z => sink(z)); // OK!
	
	new Promise((resolve, reject) => reject(source)).catch(x => sink(x)); // NOT OK!
	
	Promise.resolve(source).catch(() => {}).then(a => sink(a)); // NOT OK!
	
	var p5 = Promise.resolve(source);
	var p6 = p5.catch(() => {});
	var p7 = p6.then(a => sink(a)); // NOT OK!

	new Promise((resolve, reject) => reject(source)).then(() => {}).catch(x => sink(x)); // NOT OK!
	
	new Promise((resolve, reject) => reject(source)).then(() => {}, () => {}).catch(x => sink(x)); // OK!
})();