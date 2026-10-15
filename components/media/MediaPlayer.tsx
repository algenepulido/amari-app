import React from 'react';
import { ActivityIndicator, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { VideoView, useVideoPlayer } from 'expo-video';
import { useAudioPlayer, useAudioPlayerStatus } from 'expo-audio';
import { Pause, Play, X } from 'lucide-react-native';
import { colors, radius, spacing, typography } from '@/lib/theme';
import type { MediaPlayback } from '@/queries/media';

function VideoPlayerView({ uri }: { uri: string }) {
  const player = useVideoPlayer(uri, (p) => {
    p.play();
  });
  return <VideoView style={styles.video} player={player} allowsFullscreen nativeControls />;
}

function AudioPlayerView({ uri }: { uri: string }) {
  const player = useAudioPlayer({ uri });
  const status = useAudioPlayerStatus(player);

  const toggle = () => {
    if (status.playing) {
      player.pause();
    } else {
      player.play();
    }
  };

  return (
    <View style={styles.audioWrap}>
      {status.isLoaded ? (
        <Pressable onPress={toggle} style={styles.audioButton} accessibilityRole="button">
          {status.playing ? (
            <Pause color={colors.black} size={28} />
          ) : (
            <Play color={colors.black} size={28} />
          )}
        </Pressable>
      ) : (
        <ActivityIndicator color={colors.white} />
      )}
    </View>
  );
}

export function MediaPlayerModal({
  playback,
  onClose,
}: {
  playback: MediaPlayback | null;
  onClose: () => void;
}) {
  return (
    <Modal visible={!!playback} animationType="slide" onRequestClose={onClose}>
      <View style={styles.container}>
        <Pressable onPress={onClose} style={styles.close} hitSlop={12} accessibilityRole="button">
          <X color={colors.white} size={24} />
        </Pressable>

        {playback ? (
          playback.media_type === 'video' ? (
            <VideoPlayerView uri={playback.url} />
          ) : (
            <AudioPlayerView uri={playback.url} />
          )
        ) : null}

        {playback ? <Text style={styles.title}>{playback.title}</Text> : null}
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.black,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.xl,
  },
  close: {
    position: 'absolute',
    top: spacing.xxxl,
    right: spacing.xl,
    zIndex: 2,
  },
  video: {
    width: '100%',
    aspectRatio: 16 / 9,
    backgroundColor: colors.black,
    borderRadius: radius.md,
  },
  audioWrap: {
    width: 120,
    height: 120,
    alignItems: 'center',
    justifyContent: 'center',
  },
  audioButton: {
    width: 88,
    height: 88,
    borderRadius: radius.full,
    backgroundColor: colors.white,
    alignItems: 'center',
    justifyContent: 'center',
  },
  title: {
    ...typography.body,
    color: colors.white,
    marginTop: spacing.xl,
    textAlign: 'center',
  },
});
