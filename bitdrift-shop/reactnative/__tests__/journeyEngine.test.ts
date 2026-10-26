import fs from 'fs';
import path from 'path';
import {JourneyEngine, JourneyRng, type JourneyAdapter} from '../src/sim/journeyEngine';
import {specJourney} from '../src/generated/specJourney';

// Replays tools/journey/golden.json (written by the Python reference engine from
// spec/journey.yaml): for every seeded case the engine must make exactly the same
// adapter calls, in the same order, as tools/journey/engine.py.
const golden = JSON.parse(
  fs.readFileSync(path.join(__dirname, '../../tools/journey/golden.json'), 'utf8'),
);

type Fields = Record<string, string>;
const f = (m: Fields) =>
  '{' + Object.keys(m).sort().map(k => `${k}=${m[k]}`).join(', ') + '}';

class TraceAdapter implements JourneyAdapter {
  lines: string[] = [];
  constructor(private fixture: Record<string, any>) {}

  isCancelled = () => false;
  startNewSession = () => void this.lines.push('new_session');
  applyExposures = (persona: string) => void this.lines.push(`exposures ${persona}`);
  setEntity = (entity: string) => void this.lines.push(`entity ${entity}`);
  delay = async (ms: number) => void this.lines.push(`wait ${ms}`);
  navigate = async (screen: string, args: Fields) => void this.lines.push(`nav ${screen} ${f(args)}`);
  callApi = async (endpoint: string, args: Fields) => {
    this.lines.push(`api ${endpoint} ${f(args)}`);
    if ((this.fixture.fail ?? []).includes(endpoint)) {
      return null;
    }
    return this.fixture[endpoint] ?? {};
  };
  log = (level: string, event: string, fields: Fields) =>
    void this.lines.push(`log ${level} ${event} ${f(fields)}`);
  startSpan = (name: string, parent: unknown, fields: Fields) => {
    this.lines.push(`span_start ${name} ${parent ?? '-'} ${f(fields)}`);
    return name;
  };
  endSpan = (handle: unknown, result: string, fields: Fields) =>
    void this.lines.push(`span_end ${handle} ${result} ${f(fields)}`);
  addField = (key: string, value: string) => void this.lines.push(`field ${key}=${value}`);
  injectFault = (id: string) => void this.lines.push(`fault ${id}`);
  fireCrash = () => void this.lines.push('crash');
}

test('mulberry32 matches the reference values', () => {
  const rng = new JourneyRng(42);
  expect(rng.next()).toBe(0.6011037519201636);
  expect(rng.next()).toBe(0.44829055899754167);
  expect(JourneyRng.journeySeed(2147483647, 4)).toBe(Number((2147483647n * 1000003n + 4n) % 4294967296n));
});

describe('golden journey traces', () => {
  for (const c of golden.cases) {
    test(c.name, async () => {
      const adapter = new TraceAdapter(golden.fixture);
      const engine = new JourneyEngine(specJourney, adapter);
      for (let run = 1; run <= c.runs; run++) {
        const outcome = await engine.run(c.persona, run, c.sim_seed, c.toggles, c.infinite);
        adapter.lines.push(`outcome ${outcome}`);
      }
      const want: string[] = c.trace;
      const i = want.findIndex((line, n) => line !== adapter.lines[n]);
      const diff = i >= 0 ? i : want.length < adapter.lines.length ? want.length : -1;
      expect({line: diff, want: want[diff], got: adapter.lines[diff]}).toEqual({
        line: -1,
        want: undefined,
        got: undefined,
      });
    });
  }
});
