// Some TypeScript code for testing
interface TestInterface {
    id: number;
    name: string;
}

class TestClass implements TestInterface {
    constructor(
        public id: number,
        public name: string
    ) {}

    greet(): string {
        return `Hello ${this.name}!`;
    }
}