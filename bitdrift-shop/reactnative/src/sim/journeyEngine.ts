// The platform half of the shared journey: everything the interpreter needs from the app.
// SimulationContext implements it against React Navigation, ApiClient and ScreenLogger;
// the unit test implements it as a trace recorder (see tools/journey/golden.json).
export interface JourneyAdapter {
  isCancelled(): boolean;
  startNewSession(): void;
  applyExposures(persona: string): void;
  setEntity(entity: string): void;
  delay(ms: number): Promise<void>;
  navigate(screen: string, args: Record<string, string>): Promise<void>;
  /** The endpoint's parsed JSON response, or null if the call failed. */
  callApi(endpoint: string, args: Record<string, string>): Promise<Record<string, unknown> | null>;
  log(level: string, event: string, fields: Record<string, string>): void;
  /** Returns a handle passed back to endSpan (and as a child's `parent`). */
  startSpan(name: string, parent: unknown, fields: Record<string, string>): unknown;
  endSpan(handle: unknown, result: string, fields: Record<string, string>): void;
  addField(key: string, value: string): void;
  /** Persist the restart intent and perform the fault (may never return). */
  injectFault(id: string): void;
  /** Fire the next crash-loop crash. */
  fireCrash(): void;
}

/** mulberry32, bit-identical to tools/journey/engine.py and the other apps' engines. */
export class JourneyRng {
  private s: number;

  constructor(seed: number) {
    this.s = seed >>> 0;
  }

  next(): number {
    this.s = (this.s + 0x6d2b79f5) >>> 0;
    let t = this.s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t = ((t + Math.imul(t ^ (t >>> 7), t | 61)) >>> 0) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  /** journeySeed = (simSeed * 1000003 + run) mod 2^32, 0 <= simSeed < 2^31 (stays below 2^53). */
  static journeySeed(simSeed: number, run: number): number {
    return (simSeed * 1000003 + run) % 4294967296;
  }
}

type Op = Record<string, any>;
type Value = string | string[];

const TEMPLATE = /\{([A-Za-z0-9_.]+)\}/g;

// Thrown to end a journey early; the outcome is what run() returns.
class Stop {
  constructor(readonly outcome: string) {}
}

/**
 * Interprets spec/journey.yaml (compiled into specJourney). A line-for-line port of
 * tools/journey/engine.py: change the journey there and in the YAML, never here. One
 * engine per simulator, because the fault counters persist across journeys.
 */
export class JourneyEngine {
  private readonly bundle: Op;
  private readonly eligible = new Map<string, number>();

  private persona = '';
  private toggles = new Set<string>();
  private infinite = false;
  private rng = new JourneyRng(0);
  private vars: Record<string, Value> = {};
  private spans = new Map<string, unknown>();
  private crashFired = false;

  constructor(bundle: unknown, private readonly a: JourneyAdapter) {
    this.bundle = bundle as Op;
  }

  /** Runs one journey; returns its outcome (completed, cart_abandoned, fault, crash, cancelled, ...). */
  async run(
    persona: string,
    run: number,
    simSeed: number,
    toggles: Iterable<string>,
    infinite: boolean,
  ): Promise<string> {
    this.persona = persona;
    this.toggles = new Set(toggles);
    this.infinite = infinite;
    this.rng = new JourneyRng(JourneyRng.journeySeed(simSeed, run));
    this.vars = {...this.bundle.personas[persona].vars};
    this.vars.run = String(run);
    this.vars.sim_seed = String(simSeed);
    this.vars.persona = persona;
    this.spans = new Map();
    this.crashFired = false;
    try {
      await this.block(this.bundle.journey);
    } catch (e) {
      if (e instanceof Stop) {
        return e.outcome;
      }
      throw e;
    }
    return 'completed';
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  private t(s: string): string {
    return s.replace(TEMPLATE, (_, name: string) => {
      const v = this.vars[name];
      return Array.isArray(v) ? String(v.length) : v ?? '';
    });
  }

  private tm(m: Record<string, string>): Record<string, string> {
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(m)) {
      out[k] = this.t(v);
    }
    return out;
  }

  private str(name: string): string {
    const v = this.vars[name];
    return typeof v === 'string' ? v : '';
  }

  private lst(name: string): string[] {
    let v = this.vars[name];
    if (!Array.isArray(v)) {
      v = [];
      this.vars[name] = v;
    }
    return v;
  }

  private p(chance: Op): number {
    let table = chance.default;
    if (chance.by != null) {
      const key = this.str(chance.by);
      if (Object.prototype.hasOwnProperty.call(chance.cases, key)) {
        table = chance.cases[key];
      }
    }
    return table[this.persona];
  }

  // Draws for `chance` first (always), then checks every other condition.
  private condOk(op: Op): boolean {
    let ok = true;
    if (op.chance != null) {
      ok = this.rng.next() < this.p(op.chance);
    }
    if (op.toggle != null && !this.toggles.has(op.toggle)) {
      ok = false;
    }
    if (op.not_toggle != null && this.toggles.has(op.not_toggle)) {
      ok = false;
    }
    if (op.eq != null && this.str(op.eq[0]) !== op.eq[1]) {
      ok = false;
    }
    if (op.min_len != null && this.lst(op.min_len[0]).length < op.min_len[1]) {
      ok = false;
    }
    return ok;
  }

  // ── interpreter ────────────────────────────────────────────────────────────
  private async block(ops: Op[]): Promise<void> {
    for (const op of ops) {
      if (this.a.isCancelled()) {
        throw new Stop('cancelled');
      }
      await this.step(op);
    }
  }

  private async step(op: Op): Promise<void> {
    const a = this.a;
    switch (op.op) {
      case 'new_session':
        a.startNewSession();
        break;
      case 'exposures':
        a.applyExposures(this.persona);
        break;
      case 'entity': {
        const ents: string[] = this.bundle.entities;
        const entity = ents[(parseInt(this.str('run'), 10) - 1) % ents.length];
        this.vars.entity = entity;
        a.setEntity(entity);
        break;
      }
      case 'wait':
        await a.delay(op.ms);
        break;
      case 'nav':
        await a.navigate(op.screen, this.tm(op.args));
        await a.delay(this.bundle.step_delay_ms);
        break;
      case 'api': {
        const res = await a.callApi(op.endpoint, this.tm(op.args));
        for (const s of op.save) {
          const v = res != null ? res[s.key] : undefined;
          if (s.item != null) {
            const items = Array.isArray(v)
              ? v.filter(x => x != null && typeof x === 'object' && s.item in x).map(x => String(x[s.item]))
              : [];
            this.vars[s.var] = items.length > 0 ? items : [...s.default];
          } else {
            this.vars[s.var] = v != null && v !== '' ? String(v) : this.t(s.default);
          }
        }
        break;
      }
      case 'log':
        a.log(op.level, op.event, this.tm(op.fields));
        break;
      case 'span_start':
        this.startSpan(op);
        break;
      case 'span_end': {
        const h = this.spans.get(op.span);
        this.spans.delete(op.span);
        if (h !== undefined) {
          a.endSpan(h, op.result, this.tm(op.fields));
        }
        break;
      }
      case 'span': {
        // Scoped span: success when the block finishes or the journey stops inside it
        // (fault / crash / outcome); canceled when the run is cancelled.
        this.startSpan(op);
        let result = 'canceled';
        try {
          await this.block(op.do);
          result = 'success';
        } catch (e) {
          if (e instanceof Stop) {
            result = e.outcome === 'cancelled' ? 'canceled' : 'success';
          }
          throw e;
        } finally {
          const h = this.spans.get(op.span);
          this.spans.delete(op.span);
          if (h !== undefined) {
            a.endSpan(h, result, {});
          }
        }
        break;
      }
      case 'set':
        for (const [key, v] of Object.entries(op.values as Record<string, string>)) {
          this.vars[key] = this.t(v);
        }
        break;
      case 'pick': {
        let items: string[] = op.values != null ? [...op.values] : [...this.lst(op.from)];
        if (op.exclude != null) {
          const ex = this.t(op.exclude);
          items = items.filter(x => x !== ex);
        }
        const r = this.rng.next();
        this.vars[op.into] = items.length > 0 ? items[Math.floor(r * items.length)] : '';
        break;
      }
      case 'rand_int':
        this.vars[op.into] = String(op.min + Math.floor(this.rng.next() * (op.max - op.min + 1)));
        break;
      case 'choose': {
        const weights: [string, number][] = op.weights[this.persona];
        let total = 0;
        for (const [, w] of weights) {
          total += w;
        }
        const x = this.rng.next() * total;
        let pick = weights[weights.length - 1][0];
        let acc = 0;
        for (const [key, w] of weights) {
          acc += w;
          if (x < acc) {
            pick = key;
            break;
          }
        }
        if (op.into) {
          this.vars[op.into] = pick;
        }
        await this.block(op.branches[pick] ?? []);
        break;
      }
      case 'if':
        await this.block(this.condOk(op) ? op.then : op.else);
        break;
      case 'switch':
        await this.block(op.cases[this.str(op.var)] ?? op.default);
        break;
      case 'repeat': {
        const [lo, hi] = op.ranges[this.persona];
        const n = lo + Math.floor(this.rng.next() * (hi - lo + 1));
        for (let i = 0; i < n; i++) {
          await this.block(op.do);
        }
        break;
      }
      case 'for_each':
        for (const item of [...this.lst(op.list)]) {
          this.vars[op.as] = item;
          await this.block(op.do);
        }
        break;
      case 'list_add':
        this.lst(op.list).push(this.t(op.value));
        break;
      case 'list_remove_random': {
        const items = this.lst(op.list);
        const r = this.rng.next();
        this.vars[op.into] = items.length > 0 ? items.splice(Math.floor(r * items.length), 1)[0] : '';
        break;
      }
      case 'list_clear':
        this.lst(op.list).length = 0;
        break;
      case 'last': {
        const items = this.lst(op.list);
        this.vars[op.into] = items.length > 0 ? items[items.length - 1] : this.t(op.default);
        break;
      }
      case 'fault':
        this.fault(op);
        break;
      case 'crash_point':
        if (
          this.toggles.has('crash_loop') &&
          !this.crashFired &&
          (op.point === this.vars.crash_point || op.point === 'confirmation')
        ) {
          this.crashFired = true;
          a.addField('crash_journey_point', op.point);
          a.fireCrash();
          throw new Stop('crash');
        }
        break;
      case 'stop':
        throw new Stop(op.outcome);
      default:
        throw new Error(`unknown op ${op.op}`);
    }
  }

  private startSpan(op: Op): void {
    const parent = op.parent ? this.spans.get(op.parent) : undefined;
    this.spans.set(op.span, this.a.startSpan(op.span, parent, this.tm(op.fields)));
  }

  private fault(op: Op): void {
    const fid: string = op.fault;
    if (!this.toggles.has(fid)) {
      return;
    }
    const eligible = (this.eligible.get(fid) ?? 0) + 1;
    this.eligible.set(fid, eligible);
    const randomHit = this.rng.next() < op.probability;
    const forced = this.infinite && eligible >= op.force_after;
    if (!randomHit && !forced) {
      return;
    }
    this.eligible.set(fid, 0);
    this.vars.trigger_mode = randomHit ? 'random' : 'forced_infinite';
    this.a.log(op.level, op.event, this.tm(op.fields));
    this.a.injectFault(fid);
    throw new Stop('fault');
  }
}
