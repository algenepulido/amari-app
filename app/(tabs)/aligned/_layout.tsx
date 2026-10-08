import React from 'react';
import { View, Text, Pressable, StyleSheet, ActivityIndicator } from 'react-native';
import { Stack, useRouter } from 'expo-router';
import { useAuth } from '../../../providers/AuthProvider';
import { colors, typography, spacing, radius, TIER_LEVELS, TAB_VISIBILITY } from '../../../lib/theme';

export default function AlignedLayout() {
  const { tier, isLoading } = useAuth();
  const router = useRouter();

  const userLevel = TIER_LEVELS[tier as keyof typeof TIER_LEVELS] ?? 0;
  const requiredLevel = TAB_VISIBILITY.aligned; // 3 = gold

  if (isLoading) {
    return (
      <View style={styles.gate}>
        <ActivityIndicator size="small" color={colors.sand} />
      </View>
    );
  }

  if (userLevel < requiredLevel) {
    return (
      <View style={styles.gate}>
        <Text style={styles.gateTitle}>Aligned</Text>
        <Text style={styles.gateMessage}>Available from Gold membership.</Text>
        <Pressable style={styles.gateBtn} onPress={() => router.back()}>
          <Text style={styles.gateBtnText}>Dismiss</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <Stack
      screenOptions={{
        headerShown: false,
        animation: 'fade',
      }}
    />
  );
}

const styles = StyleSheet.create({
  gate: {
    flex: 1,
    backgroundColor: colors.bone,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.xl,
  },
  gateTitle: {
    fontFamily: typography.serif.medium,
    fontSize: typography.sizes.screenTitle,
    color: colors.black,
    marginBottom: 8,
  },
  gateMessage: {
    fontFamily: typography.body.regular,
    fontSize: typography.sizes.body,
    color: colors.gray,
    textAlign: 'center',
    marginBottom: 24,
  },
  gateBtn: {
    paddingVertical: 13,
    paddingHorizontal: 32,
    borderRadius: radius.md,
    backgroundColor: colors.black,
  },
  gateBtnText: {
    fontFamily: typography.body.medium,
    fontSize: typography.sizes.bodySmall,
    color: colors.white,
  },
});
