import React, { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Image, Linking, Modal, Pressable, Share, StyleSheet, Text, View } from 'react-native';
import { CameraView, useCameraPermissions, type BarcodeScanningResult } from 'expo-camera';
import QRCode from 'react-native-qrcode-svg';
import { MotiView } from 'moti';
import * as Haptics from 'expo-haptics';
import { useQueryClient } from '@tanstack/react-query';
import { colors, typography, type MembershipTier } from '@/lib/theme';
import { supabase } from '@/lib/supabase';
import { useBarcode } from '@/hooks/useBarcode';
import { ProfileMembershipCard } from './ProfileMembershipCard';

const AMARI_LOGO_DARK = require('../../assets/images/amari-logo-dark.png');

interface PassConnectResult {
  success?: boolean;
  already_connected?: boolean;
  connection_id?: string;
  display_id?: string;
  name?: string;
  error?: string;
}

interface CardPopupModalProps {
  visible: boolean;
  onClose: () => void;
  fullName: string;
  city?: string | null;
  tierLabel: string;
  tier?: MembershipTier;
  displayId: string;
  memberUuid: string;
}

export function CardPopupModal({
  visible,
  onClose,
  fullName,
  city,
  tierLabel,
  tier,
  displayId,
  memberUuid,
}: CardPopupModalProps) {
  const [mounted, setMounted] = useState(visible);
  const [scanMode, setScanMode] = useState(false);
  const [scanBusy, setScanBusy] = useState(false);
  const [scanStatus, setScanStatus] = useState('Align another member pass inside the frame.');
  const [cameraPermission, requestCameraPermission] = useCameraPermissions();
  const queryClient = useQueryClient();
  const { data: barcode, isLoading: barcodeLoading, refetch } = useBarcode();

  useEffect(() => {
    if (visible) {
      setMounted(true);
      void refetch();
      return;
    }

    setScanMode(false);
    setScanBusy(false);
    setScanStatus('Align another member pass inside the frame.');
    const timeout = setTimeout(() => setMounted(false), 420);
    return () => clearTimeout(timeout);
  }, [visible, refetch]);

  const memberProfileUrl = `https://amari.app/member/${memberUuid}`;
  const qrValue = barcode?.token ?? '';
  const expiryLabel = barcode?.expires_at
    ? new Date(barcode.expires_at).toLocaleString('en-AU', {
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
      })
    : null;
  const shareMessage = [
    `${fullName} · ${tierLabel}`,
    city || 'AMARI Member',
    displayId,
    memberProfileUrl,
  ].join('\n');

  const handleEmailPress = async () => {
    const subject = encodeURIComponent(`AMARI pass — ${fullName}`);
    const body = encodeURIComponent(`Here is my AMARI member pass.\n\n${shareMessage}`);
    const emailUrl = `mailto:?subject=${subject}&body=${body}`;

    const canOpen = await Linking.canOpenURL(emailUrl);
    if (!canOpen) {
      try {
        await Share.share({
          title: `AMARI pass — ${fullName}`,
          message: shareMessage,
        });
      } catch {
        Alert.alert('Share unavailable', 'No email or share app is available on this device.');
      }
      return;
    }

    await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    await Linking.openURL(emailUrl).catch(async () => {
      await Share.share({
        title: `AMARI pass — ${fullName}`,
        message: shareMessage,
      });
    });
  };

  const handleSharePress = async () => {
    try {
      await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      await Share.share({
        title: `AMARI pass — ${fullName}`,
        message: shareMessage,
      });
    } catch {
      Alert.alert('Share unavailable', 'This pass could not be shared right now.');
    }
  };

  const handleScanPress = useCallback(async () => {
    const permission = cameraPermission?.granted ? cameraPermission : await requestCameraPermission();

    if (!permission.granted) {
      Alert.alert(
        'Camera permission needed',
        'AMARI needs camera access to scan another member pass.',
        [
          { text: 'Cancel', style: 'cancel' },
          { text: 'Open Settings', onPress: () => Linking.openSettings() },
        ],
      );
      return;
    }

    await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setScanStatus('Align another member pass inside the frame.');
    setScanMode(true);
  }, [cameraPermission, requestCameraPermission]);

  const handleBarcodeScanned = useCallback(
    async (result: BarcodeScanningResult) => {
      if (scanBusy || !result.data) {
        return;
      }

      setScanBusy(true);
      setScanStatus('Verifying secure pass...');

      try {
        const { data, error } = await supabase.rpc('connect_with_member_barcode', {
          p_token: result.data,
        });

        if (error) {
          throw error;
        }

        const connectResult = data as PassConnectResult;
        if (!connectResult?.success) {
          await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
          setScanStatus(connectResult?.error || 'This pass could not be verified.');
          Alert.alert('Pass not verified', connectResult?.error || 'This QR code is not a valid AMARI member pass.');
          setScanBusy(false);
          return;
        }

        await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
        setScanMode(false);
        setScanBusy(false);
        setScanStatus('Align another member pass inside the frame.');
        queryClient.invalidateQueries({ queryKey: ['aligned', 'recent-connections'] });

        Alert.alert(
          connectResult.already_connected ? 'Already connected' : 'Connection added',
          connectResult.name
            ? `${connectResult.name} is now available in your Aligned connections.`
            : 'This member is now available in your Aligned connections.',
        );
      } catch (error: any) {
        await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
        setScanStatus('Scan failed. Try again.');
        Alert.alert('Scan failed', error?.message || 'The pass could not be checked right now.');
        setScanBusy(false);
      }
    },
    [queryClient, scanBusy],
  );

  if (!mounted) {
    return null;
  }

  return (
    <Modal transparent visible onRequestClose={onClose}>
      <View style={styles.root}>
        <MotiView
          from={{ opacity: 0 }}
          animate={{ opacity: visible ? 1 : 0 }}
          transition={{ type: 'timing', duration: 400 }}
          style={styles.backdrop}
        />

        <Pressable style={StyleSheet.absoluteFillObject} onPress={onClose} />

        <View style={styles.content} pointerEvents="box-none">
          <MotiView
            from={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: visible ? 1 : 0, scale: visible ? 1 : 0.82 }}
            transition={{ type: 'spring', damping: 15, stiffness: 150 }}
            style={styles.cardWrap}
          >
            <ProfileMembershipCard
              fullName={fullName}
              city={city}
              tier={tier}
              tierLabel={tierLabel}
              displayId={displayId}
              size="expanded"
              showHint={false}
            />
          </MotiView>

          <MotiView
            from={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: visible ? 1 : 0, scale: visible ? 1 : 0.92 }}
            transition={{ type: 'timing', duration: 320, delay: 180 }}
            style={styles.qrSection}
          >
            {scanMode ? (
              <View style={styles.scannerShell}>
                <CameraView
                  active={visible && scanMode}
                  barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
                  facing="back"
                  onBarcodeScanned={scanBusy ? undefined : handleBarcodeScanned}
                  style={styles.cameraPreview}
                />
                <View pointerEvents="none" style={styles.scannerFrame}>
                  <View style={styles.scannerCornerTopLeft} />
                  <View style={styles.scannerCornerTopRight} />
                  <View style={styles.scannerCornerBottomLeft} />
                  <View style={styles.scannerCornerBottomRight} />
                </View>
                <View style={styles.scannerFooter}>
                  {scanBusy ? <ActivityIndicator color={colors.white} /> : null}
                  <Text style={styles.scannerStatus}>{scanStatus}</Text>
                  <Pressable
                    onPress={() => {
                      setScanMode(false);
                      setScanBusy(false);
                      setScanStatus('Align another member pass inside the frame.');
                    }}
                    style={styles.scannerCancelButton}
                  >
                    <Text style={styles.scannerCancelText}>Cancel scan</Text>
                  </Pressable>
                </View>
              </View>
            ) : (
              <>
                <View style={styles.qrShell}>
                  {qrValue ? (
                    <QRCode
                      value={qrValue}
                      size={156}
                      color={colors.black}
                      backgroundColor={colors.white}
                      ecl="H"
                    />
                  ) : barcodeLoading ? (
                    <View style={styles.qrState}>
                      <ActivityIndicator color={colors.black} />
                      <Text style={styles.qrStateTitle}>Generating secure pass</Text>
                      <Text style={styles.qrStateText}>Preparing today&apos;s event access code.</Text>
                    </View>
                  ) : (
                    <Pressable onPress={() => refetch()} style={styles.qrState}>
                      <Text style={styles.qrStateTitle}>Pass unavailable</Text>
                      <Text style={styles.qrStateText}>
                        Tap to retry loading your secure event access code.
                      </Text>
                    </Pressable>
                  )}
                </View>
                <Image source={AMARI_LOGO_DARK} style={styles.qrLogoMark} resizeMode="contain" />
                <Text style={styles.qrId}>{displayId}</Text>
                {expiryLabel ? <Text style={styles.qrExpiry}>Valid until {expiryLabel}</Text> : null}
              </>
            )}
          </MotiView>

          <MotiView
            from={{ opacity: 0, translateY: 10 }}
            animate={{ opacity: visible ? 1 : 0, translateY: visible ? 0 : 10 }}
            transition={{ type: 'timing', duration: 260, delay: 260 }}
            style={styles.walletRow}
          >
            <Pressable
              style={({ pressed }) => [styles.walletButton, pressed && styles.walletButtonPressed]}
              onPress={() => {
                handleEmailPress();
              }}
            >
              <Text style={styles.walletButtonText}>Email details</Text>
            </Pressable>
            <Pressable
              style={({ pressed }) => [styles.walletButton, pressed && styles.walletButtonPressed]}
              onPress={() => {
                handleSharePress();
              }}
            >
              <Text style={styles.walletButtonText}>Share to apps</Text>
            </Pressable>
            <Pressable
              style={({ pressed }) => [styles.walletButton, pressed && styles.walletButtonPressed]}
              onPress={handleScanPress}
            >
              <Text style={styles.walletButtonText}>Scan pass</Text>
            </Pressable>
          </MotiView>

          <MotiView
            from={{ opacity: 0, translateY: 10 }}
            animate={{ opacity: visible ? 1 : 0, translateY: visible ? 0 : 10 }}
            transition={{ type: 'timing', duration: 220, delay: 320 }}
          >
            <Text style={styles.dismissText}>
              The QR rotates daily. Scan another member pass to connect, or share yours through native apps.
            </Text>
          </MotiView>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  backdrop: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: colors.overlayHeavy,
  },
  content: {
    width: '100%',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingBottom: 40,
  },
  cardWrap: {
    width: '100%',
    alignItems: 'center',
  },
  qrSection: {
    marginTop: 24,
    alignItems: 'center',
  },
  qrShell: {
    width: 200,
    height: 200,
    padding: 22,
    borderRadius: 18,
    backgroundColor: colors.white,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 20,
    elevation: 10,
  },
  scannerShell: {
    width: 248,
    height: 300,
    overflow: 'hidden',
    borderRadius: 22,
    backgroundColor: colors.black,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.14)',
  },
  cameraPreview: {
    ...StyleSheet.absoluteFillObject,
  },
  scannerFrame: {
    position: 'absolute',
    top: 38,
    left: 36,
    right: 36,
    height: 176,
  },
  scannerCornerTopLeft: {
    position: 'absolute',
    left: 0,
    top: 0,
    width: 32,
    height: 32,
    borderLeftWidth: 3,
    borderTopWidth: 3,
    borderColor: '#E6CF8C',
  },
  scannerCornerTopRight: {
    position: 'absolute',
    right: 0,
    top: 0,
    width: 32,
    height: 32,
    borderRightWidth: 3,
    borderTopWidth: 3,
    borderColor: '#E6CF8C',
  },
  scannerCornerBottomLeft: {
    position: 'absolute',
    left: 0,
    bottom: 0,
    width: 32,
    height: 32,
    borderLeftWidth: 3,
    borderBottomWidth: 3,
    borderColor: '#E6CF8C',
  },
  scannerCornerBottomRight: {
    position: 'absolute',
    right: 0,
    bottom: 0,
    width: 32,
    height: 32,
    borderRightWidth: 3,
    borderBottomWidth: 3,
    borderColor: '#E6CF8C',
  },
  scannerFooter: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    minHeight: 86,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: 'rgba(0,0,0,0.58)',
  },
  scannerStatus: {
    marginTop: 6,
    fontFamily: typography.body.medium,
    fontSize: 12,
    lineHeight: 16,
    color: colors.white,
    textAlign: 'center',
  },
  scannerCancelButton: {
    marginTop: 10,
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.16)',
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  scannerCancelText: {
    fontFamily: typography.body.semiBold,
    fontSize: 11,
    color: 'rgba(255,255,255,0.82)',
  },
  qrState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 16,
  },
  qrStateTitle: {
    marginTop: 10,
    fontFamily: typography.body.semiBold,
    fontSize: 12,
    color: colors.black,
    textAlign: 'center',
  },
  qrStateText: {
    marginTop: 6,
    fontFamily: typography.body.regular,
    fontSize: 11,
    color: 'rgba(10,10,10,0.56)',
    lineHeight: 16,
    textAlign: 'center',
  },
  qrLogoMark: {
    width: 30,
    height: 30,
    marginTop: 14,
    opacity: 0.9,
  },
  qrId: {
    marginTop: 10,
    fontFamily: typography.mono.regular,
    fontSize: 10,
    color: 'rgba(255,255,255,0.50)',
    letterSpacing: 2.5,
  },
  qrExpiry: {
    marginTop: 8,
    fontFamily: typography.body.medium,
    fontSize: 11,
    color: 'rgba(255,255,255,0.58)',
  },
  walletRow: {
    marginTop: 18,
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'center',
    gap: 10,
  },
  walletButton: {
    flexGrow: 1,
    minWidth: 120,
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    backgroundColor: 'rgba(255,255,255,0.06)',
  },
  walletButtonPressed: {
    transform: [{ scale: 0.97 }],
    borderColor: 'rgba(196,162,101,0.32)',
    backgroundColor: 'rgba(255,255,255,0.10)',
  },
  walletButtonText: {
    fontFamily: typography.body.semiBold,
    fontSize: 11,
    color: 'rgba(255,255,255,0.82)',
  },
  dismissText: {
    marginTop: 20,
    fontFamily: typography.body.medium,
    fontSize: 11,
    color: 'rgba(255,255,255,0.42)',
    letterSpacing: 1,
  },
});
