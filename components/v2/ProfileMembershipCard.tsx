import React, { useMemo } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { MotiView } from 'moti';
import { colors, typography, type MembershipTier } from '@/lib/theme';
import { AmariEmblem } from './AmariEmblem';

interface ProfileMembershipCardProps {
  fullName: string;
  city?: string | null;
  tier?: MembershipTier;
  tierLabel: string;
  displayId: string;
  onPress?: () => void;
  showHint?: boolean;
  size?: 'compact' | 'expanded';
}

type TierCardPalette = {
  avatarColors: [string, string];
  avatarTextColor: string;
  cardColors: [string, string, string];
  hintColor: string;
  locationColor: string;
  memberIdColor: string;
  orbGold: string;
  orbTeal: string;
  orbViolet: string;
  ringColors: [string, string, string, string];
  tierPillBackground: string;
  tierPillBorder: string;
  tierTextColor: string;
};

function resolveTierKey(tier?: string, tierLabel?: string): MembershipTier {
  const value = (tier ?? '').toLowerCase();
  if (value === 'laureate' || value === 'platinum' || value === 'gold' || value === 'silver' || value === 'member') {
    return value as MembershipTier;
  }
  const label = (tierLabel ?? '').toLowerCase();
  if (label.includes('laureate')) return 'laureate';
  if (label.includes('platinum')) return 'platinum';
  if (label.includes('gold')) return 'gold';
  if (label.includes('silver')) return 'silver';
  return 'member';
}

function getTierPalette(tier?: string, tierLabel?: string): TierCardPalette {
  const key = resolveTierKey(tier, tierLabel);

  if (key === 'silver') {
    return {
      avatarColors: ['#F2F4F7', '#BCC4D0'],
      avatarTextColor: colors.black,
      cardColors: ['#191B20', '#101216', '#181B21'],
      hintColor: 'rgba(222,226,232,0.48)',
      locationColor: 'rgba(235,239,245,0.64)',
      memberIdColor: 'rgba(228,232,238,0.48)',
      orbGold: 'rgba(197,205,217,0.16)',
      orbTeal: 'rgba(125,160,188,0.12)',
      orbViolet: 'rgba(132,144,182,0.12)',
      ringColors: [
        'rgba(221,225,231,0.34)',
        'rgba(147,161,188,0.18)',
        'rgba(109,135,170,0.14)',
        'rgba(221,225,231,0.30)',
      ],
      tierPillBackground: 'rgba(255,255,255,0.06)',
      tierPillBorder: 'rgba(221,225,231,0.22)',
      tierTextColor: '#DDE1E7',
    };
  }

  if (key === 'platinum') {
    return {
      avatarColors: [colors.tierPlatinum, colors.gold],
      avatarTextColor: colors.white,
      cardColors: ['#221216', '#12090D', '#1B0F13'],
      hintColor: 'rgba(255,236,221,0.48)',
      locationColor: 'rgba(255,235,221,0.62)',
      memberIdColor: 'rgba(255,226,204,0.45)',
      orbGold: 'rgba(196,162,101,0.18)',
      orbTeal: 'rgba(155,98,109,0.12)',
      orbViolet: 'rgba(114,47,55,0.18)',
      ringColors: [
        'rgba(196,162,101,0.34)',
        'rgba(114,47,55,0.22)',
        'rgba(176,102,112,0.14)',
        'rgba(196,162,101,0.30)',
      ],
      tierPillBackground: 'rgba(255,255,255,0.04)',
      tierPillBorder: 'rgba(196,162,101,0.20)',
      tierTextColor: colors.goldLight,
    };
  }

  if (key === 'laureate') {
    return {
      avatarColors: ['#F3DEB0', '#D8AF65'],
      avatarTextColor: colors.black,
      cardColors: ['#111111', '#050505', '#171109'],
      hintColor: 'rgba(255,243,215,0.48)',
      locationColor: 'rgba(255,240,210,0.66)',
      memberIdColor: 'rgba(255,235,199,0.46)',
      orbGold: 'rgba(201,169,98,0.22)',
      orbTeal: 'rgba(145,108,55,0.12)',
      orbViolet: 'rgba(92,74,42,0.12)',
      ringColors: [
        'rgba(243,222,176,0.34)',
        'rgba(201,169,98,0.22)',
        'rgba(168,132,71,0.14)',
        'rgba(243,222,176,0.30)',
      ],
      tierPillBackground: 'rgba(255,255,255,0.04)',
      tierPillBorder: 'rgba(243,222,176,0.18)',
      tierTextColor: '#F3DEB0',
    };
  }

  if (key === 'gold') {
    return {
      avatarColors: [colors.goldDark, colors.gold],
      avatarTextColor: colors.black,
      cardColors: [colors.cardBase, colors.cardDark, colors.cardWarm],
      hintColor: 'rgba(255,255,255,0.44)',
      locationColor: 'rgba(255,255,255,0.60)',
      memberIdColor: 'rgba(255,255,255,0.48)',
      orbGold: 'rgba(196,162,101,0.18)',
      orbTeal: 'rgba(101,170,196,0.10)',
      orbViolet: 'rgba(166,132,204,0.10)',
      ringColors: [
        'rgba(196,162,101,0.40)',
        'rgba(166,132,204,0.18)',
        'rgba(101,170,196,0.16)',
        'rgba(196,162,101,0.36)',
      ],
      tierPillBackground: 'rgba(0,0,0,0.08)',
      tierPillBorder: 'rgba(196,162,101,0.25)',
      tierTextColor: colors.gold,
    };
  }

  return {
    avatarColors: ['#4A4E57', '#2B2E34'],
    avatarTextColor: colors.white,
    cardColors: ['#191B20', '#101216', '#15171B'],
    hintColor: 'rgba(255,255,255,0.40)',
    locationColor: 'rgba(235,238,243,0.58)',
    memberIdColor: 'rgba(228,232,238,0.44)',
    orbGold: 'rgba(255,255,255,0.05)',
    orbTeal: 'rgba(160,175,195,0.08)',
    orbViolet: 'rgba(150,158,180,0.08)',
    ringColors: [
      'rgba(214,218,226,0.24)',
      'rgba(150,160,180,0.14)',
      'rgba(120,132,154,0.10)',
      'rgba(214,218,226,0.20)',
    ],
    tierPillBackground: 'rgba(255,255,255,0.05)',
    tierPillBorder: 'rgba(214,218,226,0.18)',
    tierTextColor: 'rgba(226,230,236,0.92)',
  };
}

export function ProfileMembershipCard({
  fullName,
  city,
  tier,
  tierLabel,
  displayId,
  onPress,
  showHint = true,
  size = 'compact',
}: ProfileMembershipCardProps) {
  const initials = useMemo(() => {
    return fullName
      .split(' ')
      .filter(Boolean)
      .map((part) => part[0])
      .join('')
      .slice(0, 2)
      .toUpperCase() || 'AM';
  }, [fullName]);

  const isExpanded = size === 'expanded';
  const palette = useMemo(() => getTierPalette(tier, tierLabel), [tier, tierLabel]);

  return (
    <Pressable
      onPress={onPress}
      disabled={!onPress}
      style={({ pressed }) => [
        styles.shell,
        isExpanded && styles.shellExpanded,
        pressed && onPress ? styles.shellPressed : null,
      ]}
      accessibilityRole={onPress ? 'button' : undefined}
      accessibilityLabel={onPress ? 'Open your AMARI pass' : undefined}
    >
      <LinearGradient
        colors={palette.cardColors}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={[styles.card, isExpanded && styles.cardExpanded]}
      >
        <View style={styles.grain} />

        <MotiView
          from={{ rotate: '0deg', scale: 1.45 }}
          animate={{ rotate: '360deg', scale: 1.55 }}
          transition={{ type: 'timing', duration: 10000, loop: true }}
          style={styles.ambientRing}
        >
          <LinearGradient
            colors={palette.ringColors}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
            style={styles.ambientRingFill}
          />
        </MotiView>

        <MotiView
          from={{ translateX: -24, rotate: '-2deg', opacity: 0.55 }}
          animate={{ translateX: 26, rotate: '1deg', opacity: 0.92 }}
          transition={{ type: 'timing', duration: 5000, loop: true }}
          style={[styles.prismaticOrb, styles.goldOrb, { backgroundColor: palette.orbGold }]}
        />
        <MotiView
          from={{ translateX: 18, translateY: -12, rotate: '2deg', opacity: 0.45 }}
          animate={{ translateX: -16, translateY: 18, rotate: '-1deg', opacity: 0.75 }}
          transition={{ type: 'timing', duration: 5200, loop: true }}
          style={[styles.prismaticOrb, styles.violetOrb, { backgroundColor: palette.orbViolet }]}
        />
        <MotiView
          from={{ translateX: -12, translateY: 18, rotate: '0deg', opacity: 0.35 }}
          animate={{ translateX: 22, translateY: -6, rotate: '3deg', opacity: 0.65 }}
          transition={{ type: 'timing', duration: 5400, loop: true }}
          style={[styles.prismaticOrb, styles.tealOrb, { backgroundColor: palette.orbTeal }]}
        />

        <MotiView
          from={{ translateX: -280 }}
          animate={{ translateX: 280 }}
          transition={{ type: 'timing', duration: 5000, loop: true }}
          style={styles.shimmerWrap}
        >
          <LinearGradient
            colors={[
              'transparent',
              'rgba(196,162,101,0.05)',
              'rgba(212,184,122,0.10)',
              'rgba(255,255,255,0.08)',
              'rgba(180,160,220,0.06)',
              'rgba(196,162,101,0.08)',
              'transparent',
            ]}
            start={{ x: 0, y: 0.5 }}
            end={{ x: 1, y: 0.5 }}
            style={styles.shimmer}
          />
        </MotiView>

        <View style={styles.bottomLine} />

        <View style={styles.watermark}>
          <AmariEmblem size={isExpanded ? 64 : 52} variant="dark" />
        </View>

        <View style={[styles.inner, isExpanded && styles.innerExpanded]}>
          <View style={styles.topRow}>
            <Text style={styles.brand}>AMARI</Text>
            <View style={[styles.tierPill, { backgroundColor: palette.tierPillBackground, borderColor: palette.tierPillBorder }]}>
              <Text style={[styles.tierText, { color: palette.tierTextColor }]}>{tierLabel}</Text>
            </View>
          </View>

          <View style={styles.middleRow}>
            <LinearGradient
              colors={palette.avatarColors}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 1 }}
              style={[styles.avatar, isExpanded && styles.avatarExpanded]}
            >
              <Text style={[styles.avatarText, isExpanded && styles.avatarTextExpanded, { color: palette.avatarTextColor }]}>
                {initials}
              </Text>
            </LinearGradient>

            <View style={styles.identity}>
              <Text style={[styles.name, isExpanded && styles.nameExpanded]} numberOfLines={2}>
                {fullName}
              </Text>
              <Text style={[styles.location, { color: palette.locationColor }]} numberOfLines={1}>
                {city || 'Location pending'}
              </Text>
            </View>
          </View>

          <View style={styles.bottomRow}>
            <Text style={[styles.memberId, { color: palette.memberIdColor }]} numberOfLines={1}>
              {displayId}
            </Text>
            {showHint ? (
              <MotiView
                from={{ opacity: 0.45 }}
                animate={{ opacity: 1 }}
                transition={{ type: 'timing', duration: 2000, loop: true }}
              >
                <Text style={[styles.hint, { color: palette.hintColor }]}>Tap for pass</Text>
              </MotiView>
            ) : null}
          </View>
        </View>
      </LinearGradient>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  shell: {
    width: '100%',
    borderRadius: 16,
  },
  shellExpanded: {
    width: '88%',
    maxWidth: 380,
  },
  shellPressed: {
    transform: [{ scale: 0.98 }],
  },
  card: {
    width: '100%',
    aspectRatio: 1.6,
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: '#000000',
    shadowOffset: { width: 0, height: 12 },
    shadowOpacity: 0.15,
    shadowRadius: 32,
    elevation: 12,
  },
  cardExpanded: {
    borderRadius: 20,
  },
  grain: {
    ...StyleSheet.absoluteFillObject,
    opacity: 0.045,
    backgroundColor: 'rgba(255,255,255,0.02)',
  },
  ambientRing: {
    position: 'absolute',
    top: -110,
    right: -80,
    width: 300,
    height: 300,
    opacity: 0.25,
  },
  ambientRingFill: {
    flex: 1,
    borderRadius: 180,
  },
  prismaticOrb: {
    position: 'absolute',
    width: 180,
    height: 140,
    borderRadius: 120,
  },
  goldOrb: {
    left: -34,
    top: 28,
  },
  violetOrb: {
    right: -30,
    top: 10,
  },
  tealOrb: {
    bottom: -18,
    left: 70,
  },
  shimmerWrap: {
    position: 'absolute',
    top: -20,
    bottom: -20,
    width: 220,
    opacity: 0.9,
  },
  shimmer: {
    flex: 1,
    transform: [{ rotate: '16deg' }],
  },
  bottomLine: {
    position: 'absolute',
    left: 22,
    right: 22,
    bottom: 0,
    height: 1,
    backgroundColor: 'rgba(196,162,101,0.28)',
  },
  watermark: {
    position: 'absolute',
    right: 18,
    bottom: 14,
    opacity: 0.05,
  },
  inner: {
    flex: 1,
    paddingHorizontal: 22,
    paddingTop: 20,
    paddingBottom: 18,
    justifyContent: 'space-between',
  },
  innerExpanded: {
    paddingBottom: 20,
  },
  topRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
  },
  brand: {
    fontFamily: typography.body.bold,
    fontSize: 13,
    color: colors.white,
    letterSpacing: 5,
  },
  tierPill: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 3,
    borderWidth: 1,
  },
  tierText: {
    fontFamily: typography.mono.medium,
    fontSize: 9,
    letterSpacing: 2,
  },
  middleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
  },
  avatar: {
    width: 48,
    height: 48,
    borderRadius: 24,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: colors.gold,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.18,
    shadowRadius: 10,
  },
  avatarExpanded: {
    width: 56,
    height: 56,
    borderRadius: 28,
  },
  avatarText: {
    fontFamily: typography.serif.medium,
    fontSize: 19,
  },
  avatarTextExpanded: {
    fontSize: 22,
  },
  identity: {
    flex: 1,
  },
  name: {
    fontFamily: typography.serif.medium,
    fontSize: 21,
    color: colors.white,
    lineHeight: 24,
  },
  nameExpanded: {
    fontSize: 23,
    lineHeight: 26,
  },
  location: {
    marginTop: 2,
    fontFamily: typography.body.regular,
    fontSize: 11,
  },
  bottomRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
  },
  memberId: {
    flex: 1,
    paddingRight: 12,
    fontFamily: typography.mono.regular,
    fontSize: 9,
    letterSpacing: 1.5,
  },
  hint: {
    fontFamily: typography.body.medium,
    fontSize: 9,
    letterSpacing: 0.5,
  },
});
