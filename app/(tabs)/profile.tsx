import React, { useMemo, useRef, useState } from 'react';
import {
  Linking,
  Alert,
  NativeScrollEvent,
  NativeSyntheticEvent,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
  useWindowDimensions,
} from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import * as Haptics from 'expo-haptics';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '@/providers/AuthProvider';
import { useMyProfile, useUpdateProfile } from '@/queries/members';
import { supabase } from '@/lib/supabase';
import { ReportIssueSheet } from '@/components/v2/ReportIssueSheet';
import { colors, radius, spacing, TIER_DISPLAY_NAMES, typography } from '@/lib/theme';
import { EditFieldModal } from '@/components/EditFieldModal';
import { CardPopupModal } from '@/components/v2/CardPopupModal';
import { CanvasTile } from '@/components/v2/CanvasTile';
import { EmblemFooter } from '@/components/v2/EmblemFooter';
import { InterestedCard } from '@/components/v2/InterestedCard';
import { ProfileMembershipCard } from '@/components/v2/ProfileMembershipCard';
import { ProfileTabSwitcher } from '@/components/v2/ProfileTabSwitcher';
import { ChevronRight } from '@/components/v2/TabIcons';
import type { AlignedTile } from '@/types/database';

type EditableFieldKey =
  | 'full_name'
  | 'city'
  | 'company'
  | 'industry'
  | 'interests'
  | 'bio';

interface EditFieldState {
  key: EditableFieldKey;
  label: string;
  value: string;
  placeholder?: string;
  multiline?: boolean;
}

type ProfileTile = Pick<
  AlignedTile,
  'id' | 'type' | 'description' | 'tags' | 'is_active' | 'created_at' | 'location'
>;

interface InterestedProject {
  id: string;
  expressedAt: string | null;
  category: string;
  title: string;
  author: string;
}

const TAB_LABELS = ['My Projects', 'Interested In', 'Account'];

function sentenceCase(value: string) {
  return value
    .split(/[-_]/g)
    .filter(Boolean)
    .map((part) => part.slice(0, 1).toUpperCase() + part.slice(1))
    .join(' ');
}

function choosePalette(tile: ProfileTile, index: number): 'warm' | 'navy' | 'forest' | 'wine' | 'smoke' {
  const source = `${tile.type} ${(tile.tags || []).join(' ')} ${tile.description}`.toLowerCase();

  if (/(finance|fund|invest|capital|venture)/.test(source)) {
    return 'warm';
  }
  if (/(community|collective|housing|network)/.test(source)) {
    return 'navy';
  }
  if (/(health|care|impact|climate|policy|research)/.test(source)) {
    return 'forest';
  }
  if (/(event|summit|media|creative|culture|story)/.test(source)) {
    return 'wine';
  }

  return ['warm', 'navy', 'forest', 'wine', 'smoke'][index % 5] as
    | 'warm'
    | 'navy'
    | 'forest'
    | 'wine'
    | 'smoke';
}

function tileCategory(tile: ProfileTile) {
  return sentenceCase(tile.tags?.[0] || tile.type || 'Project');
}

function tileTitle(tile: ProfileTile, fallbackTitle?: string | null) {
  if (fallbackTitle?.trim()) {
    return fallbackTitle.trim();
  }

  return tile.description.trim() || 'Untitled project';
}

function tileDescription(tile: ProfileTile, title: string) {
  const description = tile.description.trim();
  if (!description || description === title) {
    return null;
  }

  return description;
}

function tileStatus(tile: ProfileTile, index: number) {
  if (!tile.is_active) {
    return 'Paused';
  }
  if (tile.type === 'project' && index === 0) {
    return 'Active';
  }
  if (tile.type === 'project') {
    return 'Building';
  }
  return 'Exploring';
}

function AccountSectionLabel({ children }: { children: string }) {
  return <Text style={styles.sectionLabel}>{children}</Text>;
}

function AccountRow({
  label,
  value,
  emptyLabel,
  onPress,
  isLast = false,
  danger = false,
}: {
  label: string;
  value?: string | null;
  emptyLabel?: string;
  onPress?: () => void | Promise<void>;
  isLast?: boolean;
  danger?: boolean;
}) {
  const displayValue = value?.trim() || emptyLabel || '';
  const isEmpty = !value?.trim();

  return (
    <Pressable
      onPress={
        onPress
          ? async () => {
              await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
              await onPress();
            }
          : undefined
      }
      disabled={!onPress}
      style={({ pressed }) => [
        styles.accountRow,
        !isLast ? styles.accountRowBorder : null,
        pressed && onPress ? styles.accountRowPressed : null,
      ]}
      accessibilityRole={onPress ? 'button' : undefined}
    >
      <View style={styles.accountRowCopy}>
        <Text style={styles.accountRowLabel}>{label}</Text>
        <Text style={[styles.accountRowValue, isEmpty ? styles.accountRowValueEmpty : null, danger ? styles.accountRowValueDanger : null]}>
          {displayValue}
        </Text>
      </View>
      <ChevronRight color={danger ? 'rgba(180,68,68,0.20)' : 'rgba(0,0,0,0.10)'} size={14} />
    </Pressable>
  );
}

export default function ProfileScreen() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const { width } = useWindowDimensions();
  const pagerRef = useRef<ScrollView>(null);
  const { user, tier } = useAuth();
  const { data: profile } = useMyProfile();
  const updateProfile = useUpdateProfile();

  const [activeTab, setActiveTab] = useState(0);
  const [showCardPopup, setShowCardPopup] = useState(false);
  const [editField, setEditField] = useState<EditFieldState | null>(null);
  const [panelHeights, setPanelHeights] = useState<Record<number, number>>({});

  const { data: myTiles = [] } = useQuery<ProfileTile[]>({
    queryKey: ['profile', 'my-project-tiles', user?.id],
    queryFn: async () => {
      if (!user?.id) {
        return [];
      }

      const { data, error } = await supabase
        .from('aligned_tiles')
        .select('id, type, description, tags, is_active, created_at, location')
        .eq('user_id', user.id)
        .eq('type', 'project')
        .order('created_at', { ascending: false });

      if (error) {
        throw error;
      }

      return (data || []).sort((left, right) => {
        if (left.is_active === right.is_active) {
          return new Date(right.created_at).getTime() - new Date(left.created_at).getTime();
        }
        return left.is_active ? -1 : 1;
      });
    },
    enabled: !!user?.id,
  });

  const { data: interestedProjects = [] } = useQuery<InterestedProject[]>({
    queryKey: ['profile', 'aligned-interests', user?.id],
    queryFn: async () => {
      if (!user?.id) {
        return [];
      }

      const { data: bookmarkRows, error: bookmarkError } = await supabase
        .from('project_bookmarks')
        .select('id, project_id, created_at')
        .eq('member_id', user.id)
        .order('created_at', { ascending: false });

      if (bookmarkError) {
        throw bookmarkError;
      }

      if (!bookmarkRows?.length) {
        return [];
      }

      const projectIds = bookmarkRows.map((row) => row.project_id);
      const { data: projects, error: projectError } = await supabase
        .from('map_cache_projects')
        .select('project_id, name, description, category')
        .in('project_id', projectIds);

      if (projectError || !projects) {
        return bookmarkRows.map((row, index) => ({
          id: row.id,
          expressedAt: row.created_at,
          category: 'Project',
          title: `Saved project ${index + 1}`,
          author: 'Project creator',
        }));
      }

      const projectMap = new Map(projects.map((project) => [project.project_id, project]));

      return bookmarkRows.map((row) => {
        const project = projectMap.get(row.project_id);
        if (!project) {
          return {
            id: row.id,
            expressedAt: row.created_at,
            category: 'Project',
            title: 'Saved project',
            author: 'Project creator',
          };
        }

        return {
          id: row.id,
          expressedAt: row.created_at,
          category: sentenceCase(project.category || 'Project'),
          title: project.name || project.description || 'Saved project',
          author: 'Project creator',
        };
      });
    },
    enabled: !!user?.id,
  });

  const fullName = profile?.full_name?.trim() || 'AMARI Member';
  const tierLabel = tier ? TIER_DISPLAY_NAMES[tier] || tier.toUpperCase() : 'MEMBER';
  const displayId = profile?.display_id || `AMARI-${new Date().getFullYear()}-0000`;
  const locationLabel = profile?.city?.trim() || 'Australia';
  const currentProjectLabel = profile?.current_project?.trim() || myTiles[0]?.description?.trim() || '';
  const openToLabel = Array.isArray(profile?.interests) ? profile.interests.join(', ') : '';
  const contentWidth = Math.min(Math.max(width - spacing.xl * 2, 280), 460);
  const pagerHeight = Math.max(360, ...Object.values(panelHeights));

  const projectTiles = useMemo(() => myTiles.slice(0, 3), [myTiles]);

  const heroTile = projectTiles[0];
  const secondaryLeftTile = projectTiles[1];
  const secondaryRightTile = projectTiles[2];

  const openEditor = (
    key: EditableFieldKey,
    label: string,
    value: string,
    options?: { placeholder?: string; multiline?: boolean }
  ) => {
    setEditField({
      key,
      label,
      value,
      placeholder: options?.placeholder,
      multiline: options?.multiline,
    });
  };

  const handleSave = (value: string) => {
    if (!editField) {
      return;
    }

    const payload =
      editField.key === 'interests'
        ? { interests: value.split(',').map((item) => item.trim()).filter(Boolean) }
        : { [editField.key]: value };

    updateProfile.mutate(payload as any, {
      onSuccess: () => setEditField(null),
    });
  };

  const handleSignOut = () => {
    Alert.alert('Sign Out', 'Are you sure you want to sign out?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Sign Out',
        style: 'destructive',
        onPress: async () => {
          await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
          await supabase.auth.signOut();
        },
      },
    ]);
  };

  const handleTabChange = async (index: number) => {
    setActiveTab(index);
    await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    pagerRef.current?.scrollTo({ x: width * index, animated: true });
  };

  const handlePagerEnd = (event: NativeSyntheticEvent<NativeScrollEvent>) => {
    const nextIndex = Math.round(event.nativeEvent.contentOffset.x / width);
    setActiveTab(nextIndex);
  };

  const openAlignedBoard = () => {
    router.push({ pathname: '/(tabs)/aligned', params: { view: 'board' } } as never);
  };

  const openAlignedInterests = () => {
    router.push({ pathname: '/(tabs)/aligned', params: { view: 'interests' } } as never);
  };

  const [reportOpen, setReportOpen] = useState(false);

  const handleOpenSupport = async () => {
    const subject = encodeURIComponent('AMARI support');
    const body = encodeURIComponent(`Hi AMARI,\n\nI need help with my account.\n\nMember: ${displayId}`);
    const mailtoUrl = `mailto:support@amari.app?subject=${subject}&body=${body}`;
    const canOpen = await Linking.canOpenURL(mailtoUrl);

    if (!canOpen) {
      Alert.alert('Support unavailable', 'No mail app is available on this device.');
      return;
    }

    await Linking.openURL(mailtoUrl);
  };

  const handleOpenPrivacyPolicy = async () => {
    await Linking.openURL('https://www.amarigroupau.com/privacy-policy');
  };

  const handleRequestAccountDeletion = () => {
    Alert.alert(
      'Delete Account',
      'This will request deletion of your AMARI account and associated personal data. AMARI will complete manual deletion and confirm by email.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Request Deletion',
          style: 'destructive',
          onPress: async () => {
            try {
              const { error: deletionError } = await supabase.rpc('request_account_deletion');
              if (deletionError) throw deletionError;

              await supabase.auth.signOut();
              Alert.alert('Deletion requested', 'Your account deletion request has been recorded.');
            } catch (err: any) {
              Alert.alert('Deletion unavailable', err.message || 'Please contact AMARI support to delete your account.');
            }
          },
        },
      ],
    );
  };

  const handleOpenSettings = async () => {
    try {
      await Linking.openSettings();
    } catch {
      Alert.alert('Settings unavailable', 'System notification settings could not be opened on this device.');
    }
  };

  const setPanelHeight = (index: number, height: number) => {
    setPanelHeights((current) => (current[index] === height ? current : { ...current, [index]: height }));
  };

  return (
    <View style={[styles.container, { paddingTop: insets.top }]}>
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.cardSection}>
          <View style={{ width: contentWidth }}>
            <ProfileMembershipCard
              fullName={fullName}
              city={locationLabel}
              tier={tier}
              tierLabel={tierLabel}
              displayId={displayId}
              onPress={async () => {
                await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
                setShowCardPopup(true);
              }}
            />
          </View>
        </View>

        <ProfileTabSwitcher
          tabs={TAB_LABELS}
          activeIndex={activeTab}
          onChange={handleTabChange}
          maxWidth={contentWidth}
        />

        <View style={[styles.pagerShell, { height: pagerHeight }]}>
          <ScrollView
            ref={pagerRef}
            horizontal
            pagingEnabled
            bounces={false}
            nestedScrollEnabled
            showsHorizontalScrollIndicator={false}
            decelerationRate="fast"
            onMomentumScrollEnd={handlePagerEnd}
            scrollEventThrottle={16}
          >
            <View style={[styles.panel, { width }]} onLayout={(event) => setPanelHeight(0, event.nativeEvent.layout.height)}>
              <View style={[styles.panelInner, { width: contentWidth }]}>
                <View style={styles.counterRow}>
                  <Text style={styles.counterText}>{`${projectTiles.length} of 3 slots`}</Text>
                </View>

                <View style={styles.pinboard}>
                  {heroTile ? (
                    <CanvasTile
                      title={tileTitle(heroTile, currentProjectLabel)}
                      description={tileDescription(heroTile, tileTitle(heroTile, currentProjectLabel))}
                      category={tileCategory(heroTile)}
                      rank={1}
                      status={tileStatus(heroTile, 0)}
                      variant="hero"
                      palette={choosePalette(heroTile, 0)}
                      onPress={openAlignedBoard}
                    />
                  ) : (
                    <CanvasTile variant="hero" isAddSlot onPress={() => router.push('/(tabs)/aligned/create')} />
                  )}

                  <View style={styles.secondaryRow}>
                    {secondaryLeftTile ? (
                      <View style={styles.secondaryTile}>
                        <CanvasTile
                          title={tileTitle(secondaryLeftTile)}
                          category={tileCategory(secondaryLeftTile)}
                          rank={2}
                          status={tileStatus(secondaryLeftTile, 1)}
                          variant="left"
                          palette={choosePalette(secondaryLeftTile, 1)}
                          onPress={openAlignedBoard}
                        />
                      </View>
                    ) : (
                      <View style={styles.secondaryTile}>
                        <CanvasTile variant="left" isAddSlot onPress={() => router.push('/(tabs)/aligned/create')} />
                      </View>
                    )}

                    {secondaryRightTile ? (
                      <View style={styles.secondaryTile}>
                        <CanvasTile
                          title={tileTitle(secondaryRightTile)}
                          category={tileCategory(secondaryRightTile)}
                          rank={3}
                          status={tileStatus(secondaryRightTile, 2)}
                          variant="right"
                          palette={choosePalette(secondaryRightTile, 2)}
                          onPress={openAlignedBoard}
                        />
                      </View>
                    ) : (
                      <View style={styles.secondaryTile}>
                        <CanvasTile variant="right" isAddSlot onPress={() => router.push('/(tabs)/aligned/create')} />
                      </View>
                    )}
                  </View>
                </View>

                <EmblemFooter />
              </View>
            </View>

            <View style={[styles.panel, { width }]} onLayout={(event) => setPanelHeight(1, event.nativeEvent.layout.height)}>
              <View style={[styles.panelInner, { width: contentWidth }]}>
                <View style={styles.interestedSection}>
                  <View style={styles.interestedHeader}>
                    <View style={styles.interestedHeaderIcon}>
                      <Svg width={14} height={18} viewBox="0 0 14 18" fill="none" color={colors.goldDark}>
                        <Path
                          d="M1 1h12v16l-6-3.5L1 17V1z"
                          stroke="currentColor"
                          strokeWidth={1.2}
                          fill="rgba(196,162,101,0.1)"
                        />
                      </Svg>
                    </View>
                    <Text style={styles.interestedHeaderText}>Projects I&apos;m interested in</Text>
                  </View>

                  <View style={styles.interestedList}>
                    {interestedProjects.length ? (
                      interestedProjects.map((item) => (
                        <InterestedCard
                          key={item.id}
                          category={item.category}
                          title={item.title}
                          author={item.author}
                          onPress={openAlignedInterests}
                        />
                      ))
                    ) : (
                      <View style={styles.emptyCard}>
                        <Text style={styles.emptyTitle}>Nothing saved yet</Text>
                        <Text style={styles.emptyBody}>
                          Projects you save in Aligned will appear here for quick access.
                        </Text>
                      </View>
                    )}
                  </View>
                </View>

                <EmblemFooter />
              </View>
            </View>

            <View style={[styles.panel, { width }]} onLayout={(event) => setPanelHeight(2, event.nativeEvent.layout.height)}>
              <View style={[styles.panelInner, { width: contentWidth }]}>
                <View style={styles.accountSection}>
                  <AccountSectionLabel>Details</AccountSectionLabel>
                  <View style={styles.accountCard}>
                    <AccountRow
                      label="City"
                      value={profile?.city || ''}
                      emptyLabel="Add city"
                      onPress={() => openEditor('city', 'City', profile?.city || '', { placeholder: 'Enter your city' })}
                    />
                    <AccountRow
                      label="Company"
                      value={profile?.company || ''}
                      emptyLabel="Add company"
                      onPress={() => openEditor('company', 'Company', profile?.company || '', { placeholder: 'Enter your company' })}
                    />
                    <AccountRow
                      label="Sector"
                      value={profile?.industry || ''}
                      emptyLabel="Add sector"
                      onPress={() => openEditor('industry', 'Sector', profile?.industry || '', { placeholder: 'Enter your sector' })}
                    />
                    <AccountRow
                      label="Open to"
                      value={openToLabel}
                      emptyLabel="Add interests"
                      onPress={() =>
                        openEditor('interests', 'Open to', openToLabel, {
                          placeholder: 'Comma-separated interests',
                        })
                      }
                    />
                    <AccountRow
                      label="Current project"
                      value={currentProjectLabel}
                      emptyLabel="Set a project in Aligned"
                      isLast
                      onPress={() => router.push('/(tabs)/aligned/create')}
                    />
                  </View>

                  <View style={styles.accountSpacer} />

                  <AccountSectionLabel>Settings</AccountSectionLabel>
                  <View style={styles.accountCard}>
                    <AccountRow
                      label="Edit profile"
                      value={fullName}
                      onPress={() =>
                        openEditor('full_name', 'Full name', profile?.full_name || '', {
                          placeholder: 'Enter your full name',
                        })
                      }
                    />
                    <AccountRow
                      label="Notifications"
                      value="Manage preferences"
                      onPress={handleOpenSettings}
                    />
                    <AccountRow
                      label="Privacy"
                      value="Membership visibility"
                      onPress={() =>
                        Alert.alert(
                          'Privacy',
                          'Your membership card is visible only to you unless you share it. Project map locations stay privacy-degraded, and Australian map locations are state-level only.',
                        )
                      }
                    />
                    <AccountRow
                      label="Privacy policy"
                      value="Open policy"
                      onPress={handleOpenPrivacyPolicy}
                    />
                    <AccountRow
                      label="Report an issue"
                      value="Alert the AMARI team"
                      onPress={() => setReportOpen(true)}
                    />
                    <AccountRow
                      label="Help"
                      value="Support and guidance"
                      onPress={handleOpenSupport}
                    />
                    <AccountRow
                      label="Delete account"
                      value="Request deletion"
                      danger
                      onPress={handleRequestAccountDeletion}
                    />
                    <AccountRow
                      label="Sign out"
                      value="End current session"
                      isLast
                      danger
                      onPress={handleSignOut}
                    />
                  </View>
                </View>

                <EmblemFooter />
              </View>
            </View>
          </ScrollView>
        </View>
      </ScrollView>

      <CardPopupModal
        visible={showCardPopup}
        onClose={() => setShowCardPopup(false)}
        fullName={fullName}
        city={locationLabel}
        tierLabel={tierLabel}
        displayId={displayId}
        memberUuid={user?.id || profile?.id || ''}
      />

      <EditFieldModal
        visible={!!editField}
        onClose={() => setEditField(null)}
        onSave={handleSave}
        label={editField?.label || ''}
        currentValue={editField?.value || ''}
        placeholder={editField?.placeholder}
        multiline={editField?.multiline}
        isSaving={updateProfile.isPending}
      />
      <ReportIssueSheet onClose={() => setReportOpen(false)} visible={reportOpen} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bone,
  },
  scroll: {
    flex: 1,
  },
  content: {
    paddingBottom: 120,
  },
  cardSection: {
    paddingHorizontal: spacing.xl,
    paddingTop: 12,
  },
  pagerShell: {
    marginTop: 4,
  },
  panel: {
    paddingTop: 6,
  },
  panelInner: {
    alignSelf: 'center',
  },
  counterRow: {
    alignItems: 'flex-end',
    paddingHorizontal: spacing.xl,
  },
  counterText: {
    fontFamily: typography.mono.regular,
    fontSize: 9,
    color: 'rgba(0,0,0,0.34)',
    letterSpacing: 0.5,
  },
  pinboard: {
    paddingHorizontal: spacing.xl,
    paddingTop: 8,
  },
  secondaryRow: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 12,
  },
  secondaryTile: {
    flex: 1,
  },
  interestedSection: {
    paddingHorizontal: spacing.xl,
    paddingTop: 16,
  },
  interestedHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 12,
  },
  interestedHeaderIcon: {
    opacity: 0.5,
  },
  interestedHeaderText: {
    fontFamily: typography.body.semiBold,
    fontSize: 12,
    color: 'rgba(0,0,0,0.58)',
  },
  interestedList: {
    gap: 6,
  },
  emptyCard: {
    paddingHorizontal: 16,
    paddingVertical: 18,
    borderRadius: 14,
    backgroundColor: colors.cream,
    borderWidth: 1,
    borderColor: 'rgba(0,0,0,0.04)',
  },
  emptyTitle: {
    fontFamily: typography.serif.medium,
    fontSize: 16,
    color: colors.black,
  },
  emptyBody: {
    marginTop: 6,
    fontFamily: typography.body.regular,
    fontSize: 12,
    lineHeight: 18,
    color: colors.gray,
  },
  accountSection: {
    paddingHorizontal: spacing.xl,
    paddingTop: 24,
  },
  sectionLabel: {
    marginBottom: 10,
    fontFamily: typography.mono.regular,
    fontSize: 8,
    color: 'rgba(0,0,0,0.34)',
    letterSpacing: 2.5,
    textTransform: 'uppercase',
  },
  accountCard: {
    borderRadius: radius.md,
    overflow: 'hidden',
    backgroundColor: colors.cream,
    shadowColor: '#000000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.03,
    shadowRadius: 12,
    elevation: 3,
  },
  accountRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 18,
    paddingVertical: 14,
  },
  accountRowBorder: {
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(0,0,0,0.04)',
  },
  accountRowPressed: {
    backgroundColor: colors.warm,
  },
  accountRowCopy: {
    flex: 1,
    paddingRight: 12,
  },
  accountRowLabel: {
    fontFamily: typography.mono.regular,
    fontSize: 9,
    color: 'rgba(0,0,0,0.40)',
    letterSpacing: 1.5,
    textTransform: 'uppercase',
  },
  accountRowValue: {
    marginTop: 2,
    fontFamily: typography.body.regular,
    fontSize: 14,
    color: colors.black,
  },
  accountRowValueEmpty: {
    fontStyle: 'italic',
    fontSize: 12,
    color: 'rgba(0,0,0,0.46)',
  },
  accountRowValueDanger: {
    color: 'rgba(160,52,52,0.80)',
  },
  accountSpacer: {
    height: 24,
  },
});
