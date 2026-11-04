using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace Crumple.Desktop.Art;

internal enum Sound { Crumple, Swish, Clank, Shred, Pour, Unfold }

/// The paper's sounds, made from noise and a few tones (no audio files), mixed so several can overlap.
/// The same recipes as the Mac version's SoundBoard. Silent where there's no Windows audio device.
internal static class Sounds
{
    public static bool Enabled { get; set; } = true;
    private const int Rate = 44_100;
    private static readonly Dictionary<Sound, float[]> buffers = [];
    private static readonly Dictionary<Sound, double> lastPlayed = [];
    private static MixingSampleProvider? mixer;
    private static WaveOutEvent? output;
    private static bool failed;

    public static void Play(Sound sound, double volume = 1)
    {
        if (!Enabled || failed || !OperatingSystem.IsWindows()) return;
        // A batch clean throws many balls at once; a few overlapping sounds are enough.
        var now = M.Now;
        if (lastPlayed.TryGetValue(sound, out var last) && now - last < 0.07) return;
        lastPlayed[sound] = now;
        try
        {
            if (output == null)
            {
                mixer = new MixingSampleProvider(WaveFormat.CreateIeeeFloatWaveFormat(Rate, 1)) { ReadFully = true };
                output = new WaveOutEvent { DesiredLatency = 80 };
                output.Init(mixer);
                output.Play();
            }
            if (!buffers.TryGetValue(sound, out var samples)) buffers[sound] = samples = Synthesize(sound);
            mixer!.AddMixerInput(new VolumeSampleProvider(new BufferProvider(samples)) { Volume = (float)volume });
        }
        catch (Exception) { failed = true; } // no audio device: stay quiet
    }

    private sealed class BufferProvider(float[] samples) : ISampleProvider
    {
        private int position;
        public WaveFormat WaveFormat { get; } = WaveFormat.CreateIeeeFloatWaveFormat(Rate, 1);
        public int Read(float[] buffer, int offset, int count)
        {
            var n = Math.Min(count, samples.Length - position);
            Array.Copy(samples, position, buffer, offset, n);
            position += n;
            return n;
        }
    }

    public static float[] Synthesize(Sound sound)
    {
        var rng = new SeededRandom((ulong)sound + 11);
        float Noise() => (float)rng.Range(-1, 1);
        float[] Samples(double seconds, Func<double, double, float> make)
        {
            var count = (int)(seconds * Rate);
            var result = new float[count];
            for (var i = 0; i < count; i++) result[i] = make((double)i / Rate, (double)i / count);
            return result;
        }
        // Paper: little cracks over a hiss, high-passed so it stays crisp.
        float[] PaperSound(double seconds, double crackRate, float level)
        {
            float crack = 0;
            var raw = Samples(seconds, (_, p) =>
            {
                if (rng.Unit() < crackRate) crack = (float)rng.Range(0.4, 1);
                crack *= 0.986f;
                var envelope = (float)Math.Pow(Math.Sin(Math.PI * p), 0.6);
                return (crack * Noise() + 0.05f * Noise()) * envelope * level;
            });
            float previous = 0, output = 0;
            for (var i = 0; i < raw.Length; i++)
            {
                output = raw[i] - previous + 0.95f * output;
                previous = raw[i];
                raw[i] = output;
            }
            return raw;
        }

        float[] result;
        switch (sound)
        {
            case Sound.Crumple: result = PaperSound(0.32, 0.0028, 0.6f); break;
            case Sound.Unfold: result = PaperSound(0.45, 0.0014, 0.35f); break;
            case Sound.Swish:
            {
                // Air through the net, then the soft bump of the ball landing.
                float low = 0;
                result = Samples(0.3, (t, p) =>
                {
                    var cutoff = (float)(0.04 + 0.22 * Math.Sin(Math.PI * p));
                    low += cutoff * (Noise() - low);
                    var air = low * (float)Math.Pow(Math.Sin(Math.PI * Math.Min(1, p * 1.25)), 2) * 1.6f;
                    var bump = t > 0.2 ? (float)(Math.Sin(2 * Math.PI * 72 * (t - 0.2)) * Math.Exp(-(t - 0.2) / 0.05)) * 0.55f : 0;
                    return air + bump;
                });
                break;
            }
            case Sound.Clank:
            {
                // A wire rim being hit: a few inharmonic partials that ring out.
                (double F, double A)[] partials = [(430, 0.5), (1090, 0.35), (1720, 0.25), (2610, 0.15)];
                result = Samples(0.4, (t, _) =>
                {
                    var attack = Math.Min(1, t / 0.002);
                    var sum = 0.0;
                    for (var i = 0; i < partials.Length; i++)
                        sum += partials[i].A * Math.Sin(2 * Math.PI * partials[i].F * t) * Math.Exp(-t / (0.11 / (1 + i * 0.5)));
                    return (float)(sum * attack * 0.6);
                });
                break;
            }
            case Sound.Shred:
            {
                // A small motor and paper being cut.
                float low = 0, crack = 0;
                result = Samples(0.7, (t, p) =>
                {
                    var motor = (float)(2 * (95 * t % 1) - 1) * 0.3f;
                    if (rng.Unit() < 0.004) crack = (float)rng.Range(0.3, 0.8);
                    crack *= 0.98f;
                    low += 0.35f * (motor + crack * Noise() - low);
                    var envelope = (float)(Math.Min(1, t / 0.03) * Math.Min(1, (1 - p) / 0.18));
                    return low * envelope * 1.2f;
                });
                break;
            }
            default:
            {
                // Paper sliding out and balls dropping one after another.
                float low = 0;
                var drops = Enumerable.Range(0, 7).Select(_ => rng.Range(0.15, 0.8)).ToArray();
                result = Samples(0.95, (t, p) =>
                {
                    low += 0.15f * (Noise() - low);
                    var slide = low * (float)Math.Sin(Math.PI * p) * 0.8f;
                    var thuds = drops.Sum(start => t > start ? Math.Sin(2 * Math.PI * 95 * (t - start)) * Math.Exp(-(t - start) / 0.04) : 0);
                    return slide + (float)thuds * 0.35f;
                });
                break;
            }
        }
        var peak = result.Length == 0 ? 1 : result.Max(Math.Abs);
        var gain = peak > 0 ? 0.8f / peak : 1;
        for (var i = 0; i < result.Length; i++) result[i] *= gain;
        return result;
    }
}
