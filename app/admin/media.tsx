import React, { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useRouter } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';
import { ArrowLeft, Trash2, Upload } from 'lucide-react-native';
import * as DocumentPicker from 'expo-document-picker';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/providers/AuthProvider';
import { colors, radius, spacing } from '@/lib/theme';

const TIERS = ['member', 'silver', 'gold', 'platinum', 'laureate'] as const;

interface AdminMediaRow {
  id: string;
  media_type: string;
  title: string;
  min_tier: string;
  published: boolean;
  storage_path: string;
}

function useAdminMedia() {
  return useQuery({
    queryKey: ['admin', 'media'],
    queryFn: async (): Promise<AdminMediaRow[]> => {
      const { data, error } = await supabase
        .from('media_items')
        .select('id, media_type, title, min_tier, published, storage_path')
        .order('created_at', { ascending: false });
      if (error) throw error;
      return (data ?? []) as AdminMediaRow[];
    },
  });
}

export default function AdminMediaScreen() {
  const router = useRouter();
  const { user, isAdmin } = useAuth();
  const queryClient = useQueryClient();
  const { data: items = [], isLoading } = useAdminMedia();

  const [picked, setPicked] = useState<{ uri: string; name: string; mimeType: string } | null>(null);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [minTier, setMinTier] = useState<string>('gold');
  const [published, setPublished] = useState(false);
  const [uploading, setUploading] = useState(false);

  const mediaType = picked ? (picked.mimeType.startsWith('audio') ? 'audio' : 'video') : null;
  const refresh = () => queryClient.invalidateQueries({ queryKey: ['admin', 'media'] });

  const pickFile = async () => {
    const result = await DocumentPicker.getDocumentAsync({
      type: ['audio/*', 'video/*'],
      copyToCacheDirectory: true,
    });
    if (!result.canceled && result.assets?.[0]) {
      const asset = result.assets[0];
      setPicked({ uri: asset.uri, name: asset.name, mimeType: asset.mimeType ?? 'video/mp4' });
      if (!title) setTitle(asset.name.replace(/\.[^.]+$/, ''));
    }
  };

  const handleUpload = async () => {
    if (!picked || !title.trim() || !mediaType) {
      Alert.alert('Required', 'Pick a file and enter a title.');
      return;
    }
    setUploading(true);
    const storagePath = `${user?.id ?? 'admin'}/${Date.now()}-${picked.name}`;
    try {
      const response = await fetch(picked.uri);
      const blob = await response.blob();
      const { error: upErr } = await supabase.storage.from('media').upload(storagePath, blob, {
        contentType: picked.mimeType,
        upsert: false,
      });
      if (upErr) throw upErr;

      const { error: insErr } = await supabase.from('media_items').insert({
        media_type: mediaType,
        title: title.trim(),
        description: description.trim() || null,
        storage_path: storagePath,
        min_tier: minTier,
        published,
        created_by: user?.id ?? null,
      });
      if (insErr) {
        await supabase.storage.from('media').remove([storagePath]);
        throw insErr;
      }

      setPicked(null);
      setTitle('');
      setDescription('');
      setPublished(false);
      setMinTier('gold');
      refresh();
      Alert.alert('Media', 'Uploaded.');
    } catch (e) {
      Alert.alert('Upload failed', e instanceof Error ? e.message : 'Could not upload.');
    } finally {
      setUploading(false);
    }
  };

  const togglePublished = async (item: AdminMediaRow) => {
    const { error } = await supabase
      .from('media_items')
      .update({ published: !item.published })
      .eq('id', item.id);
    if (error) {
      Alert.alert('Error', error.message);
      return;
    }
    refresh();
  };

  const confirmRemove = (item: AdminMediaRow) => {
    Alert.alert('Delete', `Delete "${item.title}"?`, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          await supabase.storage.from('media').remove([item.storage_path]);
          const { error } = await supabase.from('media_items').delete().eq('id', item.id);
          if (error) {
            Alert.alert('Error', error.message);
            return;
          }
          refresh();
        },
      },
    ]);
  };

  if (!isAdmin) {
    return (
      <SafeAreaView style={styles.container} edges={['top']}>
        <View style={styles.center}>
          <Text style={styles.empty}>Admins only.</Text>
        </View>
      </SafeAreaView>
    );
  }

  const renderItem = ({ item }: { item: AdminMediaRow }) => (
    <View style={styles.row}>
      <View style={styles.rowBody}>
        <Text style={styles.rowTitle} numberOfLines={1}>
          {item.title}
        </Text>
        <Text style={styles.rowMeta}>
          {item.media_type} · {item.min_tier} · {item.published ? 'published' : 'draft'}
        </Text>
      </View>
      <Switch value={item.published} onValueChange={() => togglePublished(item)} />
      <Pressable onPress={() => confirmRemove(item)} hitSlop={10} style={styles.delete}>
        <Trash2 color={colors.sand} size={18} />
      </Pressable>
    </View>
  );

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} hitSlop={12} accessibilityRole="button">
          <ArrowLeft color={colors.black} size={22} />
        </Pressable>
        <Text style={styles.headerTitle}>Media</Text>
        <View style={styles.headerSpacer} />
      </View>

      <FlatList
        data={items}
        keyExtractor={(i) => i.id}
        renderItem={renderItem}
        contentContainerStyle={styles.list}
        ListHeaderComponent={
          <View style={styles.form}>
            <Pressable onPress={pickFile} style={styles.pickButton} accessibilityRole="button">
              <Upload color={colors.black} size={18} />
              <Text style={styles.pickText} numberOfLines={1}>
                {picked ? `${picked.name}  (${mediaType})` : 'Pick an audio or video file'}
              </Text>
            </Pressable>

            <TextInput
              style={styles.input}
              placeholder="Title"
              placeholderTextColor={colors.sand}
              value={title}
              onChangeText={setTitle}
            />
            <TextInput
              style={[styles.input, styles.inputMultiline]}
              placeholder="Description (optional)"
              placeholderTextColor={colors.sand}
              value={description}
              onChangeText={setDescription}
              multiline
            />

            <Text style={styles.label}>Unlocks from</Text>
            <View style={styles.tierRow}>
              {TIERS.map((t) => (
                <Pressable
                  key={t}
                  onPress={() => setMinTier(t)}
                  style={[styles.tierChip, minTier === t ? styles.tierChipActive : null]}
                >
                  <Text style={[styles.tierChipText, minTier === t ? styles.tierChipTextActive : null]}>
                    {t}
                  </Text>
                </Pressable>
              ))}
            </View>

            <View style={styles.publishRow}>
              <Text style={styles.label}>Published</Text>
              <Switch value={published} onValueChange={setPublished} />
            </View>

            <Pressable
              onPress={handleUpload}
              disabled={uploading}
              style={[styles.uploadButton, uploading ? styles.uploadButtonDisabled : null]}
              accessibilityRole="button"
            >
              {uploading ? (
                <ActivityIndicator color={colors.white} />
              ) : (
                <Text style={styles.uploadText}>Upload</Text>
              )}
            </Pressable>

            <Text style={styles.listLabel}>{isLoading ? 'Loading…' : `${items.length} item(s)`}</Text>
          </View>
        }
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bone },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.xl,
    paddingVertical: spacing.lg,
  },
  headerTitle: { fontSize: 18, fontWeight: '600', color: colors.black },
  headerSpacer: { width: 22 },
  list: { paddingHorizontal: spacing.xl, paddingBottom: spacing.xxxl },
  form: { paddingBottom: spacing.lg },
  pickButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    backgroundColor: colors.sandLight,
    borderRadius: radius.md,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
    marginBottom: spacing.md,
  },
  pickText: { flex: 1, color: colors.black, fontSize: 14 },
  input: {
    backgroundColor: colors.cream,
    borderRadius: radius.md,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
    fontSize: 15,
    color: colors.black,
    marginBottom: spacing.md,
  },
  inputMultiline: { minHeight: 64, textAlignVertical: 'top' },
  label: { fontSize: 12, fontWeight: '600', color: colors.sand, marginBottom: spacing.sm },
  tierRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm, marginBottom: spacing.lg },
  tierChip: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: radius.full,
    backgroundColor: colors.cream,
  },
  tierChipActive: { backgroundColor: colors.black },
  tierChipText: { fontSize: 12, color: colors.sand },
  tierChipTextActive: { color: colors.white },
  publishRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: spacing.lg,
  },
  uploadButton: {
    backgroundColor: colors.black,
    borderRadius: radius.md,
    paddingVertical: spacing.lg,
    alignItems: 'center',
  },
  uploadButtonDisabled: { opacity: 0.5 },
  uploadText: { color: colors.white, fontSize: 15, fontWeight: '600' },
  listLabel: {
    fontSize: 12,
    fontWeight: '600',
    color: colors.sand,
    marginTop: spacing.xxl,
    marginBottom: spacing.sm,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: spacing.md,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.sandLight,
  },
  rowBody: { flex: 1 },
  rowTitle: { fontSize: 15, fontWeight: '500', color: colors.black },
  rowMeta: { fontSize: 12, color: colors.sand, marginTop: 2 },
  delete: { padding: spacing.xs },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  empty: { fontSize: 14, color: colors.sand },
});
