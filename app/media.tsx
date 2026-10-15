import React, { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useRouter } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';
import { ArrowLeft, Headphones, Lock, Play } from 'lucide-react-native';
import { colors, radius, spacing, TIER_LEVELS } from '@/lib/theme';
import { useAuth } from '@/providers/AuthProvider';
import {
  fetchMediaPlayback,
  MediaPlaybackError,
  useMediaCatalog,
  type MediaCatalogItem,
  type MediaPlayback,
} from '@/queries/media';
import { MediaPlayerModal } from '@/components/media/MediaPlayer';

function formatDuration(seconds: number | null): string {
  if (!seconds || seconds <= 0) return '';
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export default function MediaScreen() {
  const router = useRouter();
  const { tier } = useAuth();
  const { data: items = [], isLoading } = useMediaCatalog();
  const [playback, setPlayback] = useState<MediaPlayback | null>(null);
  const [loadingId, setLoadingId] = useState<string | null>(null);

  const myLevel = TIER_LEVELS[tier as keyof typeof TIER_LEVELS] ?? 1;

  const onPressItem = async (item: MediaCatalogItem) => {
    if (loadingId) return;
    setLoadingId(item.id);
    try {
      const pb = await fetchMediaPlayback(item.id);
      setPlayback(pb);
    } catch (e) {
      const message = e instanceof MediaPlaybackError ? e.message : 'This could not be played.';
      Alert.alert('Media', message);
    } finally {
      setLoadingId(null);
    }
  };

  const renderItem = ({ item }: { item: MediaCatalogItem }) => {
    const required = TIER_LEVELS[item.min_tier as keyof typeof TIER_LEVELS] ?? 3;
    const locked = required > myLevel;
    const duration = formatDuration(item.duration_seconds);

    return (
      <Pressable
        onPress={() => onPressItem(item)}
        style={({ pressed }) => [styles.row, pressed ? styles.rowPressed : null]}
        accessibilityRole="button"
      >
        <View style={styles.thumb}>
          {item.media_type === 'video' ? (
            <Play color={colors.sand} size={20} />
          ) : (
            <Headphones color={colors.sand} size={20} />
          )}
        </View>

        <View style={styles.rowBody}>
          <Text style={styles.rowTitle} numberOfLines={2}>
            {item.title}
          </Text>
          <Text style={styles.rowMeta}>
            {item.media_type === 'video' ? 'Watch' : 'Listen'}
            {duration ? `  ·  ${duration}` : ''}
          </Text>
        </View>

        {loadingId === item.id ? (
          <ActivityIndicator color={colors.sand} />
        ) : locked ? (
          <View style={styles.lock}>
            <Lock color={colors.sand} size={14} />
            <Text style={styles.lockText}>{item.min_tier.toUpperCase()}</Text>
          </View>
        ) : null}
      </Pressable>
    );
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} hitSlop={12} accessibilityRole="button">
          <ArrowLeft color={colors.black} size={22} />
        </Pressable>
        <Text style={styles.headerTitle}>Media</Text>
        <View style={styles.headerSpacer} />
      </View>

      {isLoading ? (
        <View style={styles.center}>
          <ActivityIndicator color={colors.sand} />
        </View>
      ) : items.length === 0 ? (
        <View style={styles.center}>
          <Text style={styles.empty}>No media yet.</Text>
        </View>
      ) : (
        <FlatList
          data={items}
          keyExtractor={(i) => i.id}
          renderItem={renderItem}
          contentContainerStyle={styles.list}
        />
      )}

      <MediaPlayerModal playback={playback} onClose={() => setPlayback(null)} />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bone,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.xl,
    paddingVertical: spacing.lg,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.black,
  },
  headerSpacer: {
    width: 22,
  },
  list: {
    paddingHorizontal: spacing.xl,
    paddingBottom: spacing.xxxl,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.md,
    gap: spacing.md,
  },
  rowPressed: {
    opacity: 0.6,
  },
  thumb: {
    width: 48,
    height: 48,
    borderRadius: radius.md,
    backgroundColor: colors.sandLight,
    alignItems: 'center',
    justifyContent: 'center',
  },
  rowBody: {
    flex: 1,
  },
  rowTitle: {
    fontSize: 15,
    fontWeight: '500',
    color: colors.black,
  },
  rowMeta: {
    fontSize: 12,
    color: colors.sand,
    marginTop: 2,
  },
  lock: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  lockText: {
    fontSize: 11,
    fontWeight: '600',
    letterSpacing: 0.5,
    color: colors.sand,
  },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  empty: {
    fontSize: 14,
    color: colors.sand,
  },
});
