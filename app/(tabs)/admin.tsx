import { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, Pressable, RefreshControl } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { MotiView } from 'moti';
import { C, T, S } from '../../lib/constants';
import { useAuth } from '../../providers/AuthProvider';
import { supabase } from '../../lib/supabase';
import { LiquidGlassCard } from '../../components/ui/LiquidGlassCard';
import { GrainOverlay } from '../../components/ui/GrainOverlay';

interface AdminStats {
  totalMembers: number;
  activeMembers: number;
  codesUsed: number;
  codesRemaining: number;
  activeEvents: number;
  totalRsvps: number;
  submittedProjects: number;
  pendingProjects: number;
  submittedInterests: number;
  openIssues: number;
}

export default function AdminScreen() {
  const { isAdmin } = useAuth();
  const router = useRouter();
  const [stats, setStats] = useState<AdminStats>({
    totalMembers: 0, activeMembers: 0, codesUsed: 0,
    codesRemaining: 0, activeEvents: 0, totalRsvps: 0,
    submittedProjects: 0, pendingProjects: 0, submittedInterests: 0, openIssues: 0,
  });
  const [refreshing, setRefreshing] = useState(false);

  const fetchStats = async () => {
    const [members, codes, events, rsvps, projects, interests, openIssues] = await Promise.all([
      supabase.from('members').select('id, status', { count: 'exact', head: true }),
      supabase.from('invitation_codes').select('id, used_by', { count: 'exact' }),
      supabase.from('events').select('id', { count: 'exact' }).gte('ends_at', new Date().toISOString()),
      supabase.from('event_rsvps').select('id', { count: 'exact' }).eq('status', 'confirmed'),
      supabase.from('projects').select('id, status', { count: 'exact' }),
      supabase.from('aligned_tiles').select('id, type', { count: 'exact' }),
      supabase.from('issue_reports').select('id', { count: 'exact', head: true }).eq('status', 'open'),
    ]);

    const allCodes = codes.data || [];
    const used = allCodes.filter((c: any) => c.used_by !== null).length;

    setStats({
      totalMembers: members.count || 0,
      activeMembers: members.count || 0,
      codesUsed: used,
      codesRemaining: (codes.count || 0) - used,
      activeEvents: events.count || 0,
      totalRsvps: rsvps.count || 0,
      submittedProjects: projects.count || 0,
      pendingProjects: (projects.data || []).filter((project: any) => project.status === 'pending').length,
      submittedInterests: interests.count || 0,
      openIssues: openIssues.count || 0,
    });
  };

  useEffect(() => { fetchStats(); }, []);

  const onRefresh = async () => {
    setRefreshing(true);
    await fetchStats();
    setRefreshing(false);
  };

  if (!isAdmin) {
    return (
      <SafeAreaView style={styles.container} edges={['top']}>
        <View style={styles.centered}>
          <Text style={{ ...T.title, color: C.lightPrimary }}>Access Denied</Text>
        </View>
      </SafeAreaView>
    );
  }

  const sections = [
    {
      title: 'Members',
      subtitle: `${stats.totalMembers} total · ${stats.activeMembers} active`,
      icon: '○',
      route: '/admin/members' as const,
    },
    {
      title: 'Events',
      subtitle: `${stats.activeEvents} upcoming · ${stats.totalRsvps} RSVPs`,
      icon: '◆',
      route: '/admin/events' as const,
    },
    {
      title: 'Check-in',
      subtitle: 'Scan member passes at the door',
      icon: '▣',
      route: '/admin/checkin' as const,
    },
    {
      title: 'Issues',
      subtitle: stats.openIssues > 0 ? `${stats.openIssues} open · needs attention` : 'Member-reported issues',
      icon: '⚑',
      route: '/admin/issues' as const,
    },
    {
      title: 'Invite Codes',
      subtitle: `${stats.codesUsed} used · ${stats.codesRemaining} remaining`,
      icon: '◇',
      route: '/admin/codes' as const,
    },
    {
      title: 'Submitted Work',
      subtitle: `${stats.submittedProjects} projects · ${stats.pendingProjects} pending · ${stats.submittedInterests} interests`,
      icon: '◌',
      route: '/admin/aligned' as const,
    },
    {
      title: 'Pulse',
      subtitle: 'Manage weekly editions',
      icon: '◈',
      route: '/admin/pulse' as const,
    },
    {
      title: 'Media',
      subtitle: 'Upload audio and video',
      icon: '►',
      route: '/admin/media' as const,
    },
  ];

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Aurora background */}
      <View style={StyleSheet.absoluteFill}>
        <View style={[styles.blob, { backgroundColor: 'rgba(201,169,98,0.07)', top: -40, right: -60, width: 260, height: 260 }]} />
        <View style={[styles.blob, { backgroundColor: 'rgba(114,47,55,0.05)', bottom: 100, left: -40, width: 220, height: 220 }]} />
      </View>
      <GrainOverlay opacity={0.03} />

      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={C.lightPrimary} />}
      >
        <MotiView
          from={{ opacity: 0, translateY: -12 }}
          animate={{ opacity: 1, translateY: 0 }}
          transition={{ type: 'timing', duration: 500 }}
          style={styles.header}
        >
          <Text style={styles.eyebrow}>Command Centre</Text>
          <Text style={styles.title}>Admin</Text>
        </MotiView>

        {/* Stats Row */}
        <MotiView
          from={{ opacity: 0, translateY: 16 }}
          animate={{ opacity: 1, translateY: 0 }}
          transition={{ type: 'timing', duration: 500, delay: 100 }}
          style={styles.statsRow}
        >
          {[
            { n: stats.totalMembers, label: 'Members' },
            { n: stats.codesRemaining, label: 'Codes Left' },
            { n: stats.pendingProjects, label: 'Pending' },
          ].map((s, i) => (
            <LiquidGlassCard key={i} variant="dark" style={styles.statCard}>
              <Text style={styles.statNumber}>{s.n}</Text>
              <Text style={styles.statLabel}>{s.label}</Text>
            </LiquidGlassCard>
          ))}
        </MotiView>

        {/* Section Cards */}
        {sections.map((section, i) => (
          <MotiView
            key={section.title}
            from={{ opacity: 0, translateY: 16 }}
            animate={{ opacity: 1, translateY: 0 }}
            transition={{ type: 'timing', duration: 500, delay: 200 + i * 80 }}
          >
            <Pressable
              onPress={() => router.push(section.route as any)}
              style={({ pressed }) => [pressed && { opacity: 0.85, transform: [{ scale: 0.98 }] }]}
            >
              <LiquidGlassCard variant="dark" style={styles.sectionCard}>
                <View style={styles.sectionRow}>
                  <View style={styles.sectionIcon}>
                    <Text style={styles.sectionIconText}>{section.icon}</Text>
                  </View>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.sectionTitle}>{section.title}</Text>
                    <Text style={styles.sectionSubtitle}>{section.subtitle}</Text>
                  </View>
                  <Text style={styles.chevron}>→</Text>
                </View>
              </LiquidGlassCard>
            </Pressable>
          </MotiView>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: C.charcoal },
  centered: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  scroll: { flex: 1 },
  content: { paddingBottom: S._40 + 84 },
  blob: { position: 'absolute', borderRadius: 999, opacity: 1 },
  header: { paddingHorizontal: S._20, paddingTop: S._12 },
  eyebrow: { ...T.label, color: C.goldOnDark, marginBottom: S._4 },
  title: { ...T.hero, color: C.lightPrimary, fontSize: 32 },
  statsRow: {
    flexDirection: 'row',
    gap: S._8,
    paddingHorizontal: S._12,
    marginTop: S._24,
  },
  statCard: { flex: 1, alignItems: 'center' },
  statNumber: { ...T.stat, color: C.lightPrimary, marginBottom: S._2 },
  statLabel: { ...T.label, fontSize: 9, color: C.lightTertiary },
  sectionCard: { marginHorizontal: S._12, marginTop: S._12 },
  sectionRow: { flexDirection: 'row', alignItems: 'center', gap: S._16 },
  sectionIcon: {
    width: 40,
    height: 40,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.06)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  sectionIconText: { fontSize: 18, color: C.lightSecondary },
  sectionTitle: { ...T.cardTitle, color: C.lightPrimary },
  sectionSubtitle: { ...T.meta, color: C.lightTertiary, marginTop: S._2 },
  chevron: { ...T.body, color: C.lightFaint, fontSize: 18 },
});
